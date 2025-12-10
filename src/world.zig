const std = @import("std");
const color = @import("color.zig");
const math = std.math;
const zglfw = @import("zglfw");

const Physics = @import("physics.zig").Physics;
const KeyboardState = @import("input.zig").KeyboardState;
const PlayerController = @import("player.zig").PlayerController;
const Camera = @import("camera.zig").Camera;
const Ship = @import("ship.zig").Ship;
const Vec2 = @import("vec2.zig").Vec2;
const Tile = @import("tile.zig").Tile;
const TileObject = @import("tile_object.zig").TileObject;

pub const World = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    camera: Camera,

    objects: std.ArrayList(TileObject),
    player_controller: PlayerController,

    physics: Physics,

    last_left: zglfw.Action = .release,
    last_right: zglfw.Action = .release,

    pub fn init(allocator: std.mem.Allocator) !Self {
        var physics = try Physics.init(allocator);

        const camera = Camera.init(
            Vec2.init(0, 0),
        );

        var objects = std.ArrayList(TileObject).init(allocator);

        var ship = try TileObject.init(allocator, 16, 16, Vec2.init(0.0, 0.0), 0);
        for (0..ship.width) |y| {
            for (0..ship.height) |x| {
                // ship.tiles[y * ship.width + x] = try Tile.initEmpty(allocator);
                ship.tiles[y * ship.width + x] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
            }
        }
        // for (2..ship.width - 2) |y| {
        //     for (2..ship.height - 2) |x| {
        //         ship.tiles[y * ship.width + x] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        //     }
        // }

        var t1 = try Tile.init(allocator, .Engine, .Metal, .Ships, 67);
        t1.rotation = .West;
        ship.tiles[2 * ship.width + 2] = t1;

        var t2 = try Tile.init(allocator, .Engine, .Metal, .Ships, 65);
        t2.rotation = .East;
        ship.tiles[2 * ship.width + 13] = t2;

        var t3 = try Tile.init(allocator, .Engine, .Metal, .Ships, 67);
        t3.rotation = .West;
        ship.tiles[3 * ship.width + 2] = t3;

        var t4 = try Tile.init(allocator, .Engine, .Metal, .Ships, 65);
        t4.rotation = .East;
        ship.tiles[3 * ship.width + 13] = t4;

        var t5 = try Tile.init(allocator, .Engine, .Metal, .Ships, 66);
        t5.rotation = .South;
        ship.tiles[13 * ship.width + 7] = t5;

        var t6 = try Tile.init(allocator, .Engine, .Metal, .Ships, 66);
        t6.rotation = .South;
        ship.tiles[13 * ship.width + 8] = t6;

        ship.ship_stats = .{};
        try ship.recalculatePhysics(&physics);
        try objects.append(ship);

        var asteroid = try TileObject.init(allocator, 8, 8, Vec2.init(0.0, -140.0), 0);
        // var asteroid = try TileObject.init(allocator, 8, 8, Vec2.init(0.0, 0.0), 0);
        for (0..asteroid.width) |y| {
            for (0..asteroid.height) |x| {
                asteroid.tiles[y * asteroid.width + x] = try Tile.init(allocator, .Hull, .Metal, .Ships, 34);
            }
        }
        // for (2..asteroid.width - 2) |y| {
        //     for (2..asteroid.height - 2) |x| {
        //         asteroid.tiles[y * asteroid.width + x] = try Tile.init(allocator, .Hull, .Metal, .Ships, 34);
        //     }
        // }
        try asteroid.recalculatePhysics(&physics);
        try objects.append(asteroid);

        const player_controller = PlayerController.init(allocator, 0);

        return .{
            .allocator = allocator,
            .camera = camera,
            .objects = objects,
            .player_controller = player_controller,
            .physics = physics,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.objects.items) |*obj| {
            obj.deinit();
        }
        self.objects.deinit();
        self.physics.deinit();
    }

    pub fn update(
        self: *Self,
        dt: f32,
        keyboard_state: *const KeyboardState,
        window: *zglfw.Window,
    ) !void {
        _ = window;

        try self.physics.physics_system.update(dt, .{});

        self.player_controller.update(dt, self.objects.items, keyboard_state, &self.physics);

        const body_interface = self.physics.physics_system.getBodyInterface();

        for (self.objects.items) |*obj| {
            if (obj.body_id == .invalid) {
                continue;
            }

            const pos = body_interface.getPosition(obj.body_id);
            const rot = body_interface.getRotation(obj.body_id);

            obj.position = Vec2.init(pos[0], pos[1]);
            obj.rotation = 2.0 * std.math.atan2(rot[2], rot[3]);
        }

        // self.camera.position = self.objects.items[0].position;
    }

    pub fn onScroll(self: *Self, xoffset: f64, yoffset: f64) void {
        _ = xoffset;

        if (yoffset > 0) {
            self.camera.zoom *= 1.1;
        } else if (yoffset < 0) {
            self.camera.zoom *= 0.9;
        }

        self.camera.zoom = @max(0.1, @min(10.0, self.camera.zoom));
    }
};

pub fn scrollCallback(window: *zglfw.Window, xoffset: f64, yoffset: f64) callconv(.c) void {
    const world = zglfw.getWindowUserPointer(window, World) orelse return;

    world.onScroll(xoffset, yoffset);
}
