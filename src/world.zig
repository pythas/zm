const std = @import("std");
const color = @import("color.zig");
const math = std.math;
const zglfw = @import("zglfw");

const Physics = @import("physics.zig").Physics;
const KeyboardState = @import("input.zig").KeyboardState;
const MouseState = @import("input.zig").MouseState;
const PlayerController = @import("player.zig").PlayerController;
const Camera = @import("camera.zig").Camera;
const Ship = @import("ship.zig").Ship;
const Vec2 = @import("vec2.zig").Vec2;
const Tile = @import("tile.zig").Tile;
const TileObject = @import("tile_object.zig").TileObject;
const ship_serialization = @import("ship_serialization.zig");

pub const World = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    camera: Camera,
    player_controller: PlayerController,

    // next_object_id: u64 = 0,
    objects: std.ArrayList(TileObject),

    physics: Physics,

    pub fn init(allocator: std.mem.Allocator) !Self {
        var physics = try Physics.init(allocator);

        const camera = Camera.init(
            Vec2.init(0, 0),
        );

        var objects = std.ArrayList(TileObject).init(allocator);

        var ship = try ship_serialization.loadShip(allocator, 0, "ship.json");

        ship.ship_stats = .{};
        try ship.recalculatePhysics(&physics);
        try objects.append(ship);

        {
            var asteroid = try TileObject.init(allocator, 1, 16, 16, Vec2.init(0.0, -300.0), 0);
            for (0..asteroid.width) |y| {
                for (0..asteroid.height) |x| {
                    asteroid.tiles[y * asteroid.width + x] = try Tile.init(allocator, .Hull, .Metal, .Ships, 34);
                }
            }
            try asteroid.recalculatePhysics(&physics);
            try objects.append(asteroid);
        }

        {
            var asteroid = try TileObject.init(allocator, 2, 16, 16, Vec2.init(-200.0, -300.0), 0);
            for (0..asteroid.width) |y| {
                for (0..asteroid.height) |x| {
                    asteroid.tiles[y * asteroid.width + x] = try Tile.init(allocator, .Hull, .Metal, .Ships, 34);
                }
            }
            try asteroid.recalculatePhysics(&physics);
            try objects.append(asteroid);
        }

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

    pub fn getObjectById(self: *World, id: u64) ?*TileObject {
        for (self.objects.items) |*obj| {
            if (obj.id == id) return obj;
        }
        return null;
    }

    pub fn update(
        self: *Self,
        dt: f32,
        keyboard_state: *const KeyboardState,
        mouse_state: *const MouseState,
    ) !void {
        try self.physics.physics_system.update(dt, .{});

        try self.player_controller.update(
            dt,
            self,
            keyboard_state,
            mouse_state,
        );

        const body_interface = self.physics.physics_system.getBodyInterface();

        for (self.objects.items) |*obj| {
            if (obj.body_id == .invalid) {
                continue;
            }

            if (obj.dirty) {
                try obj.recalculatePhysics(&self.physics);
            }

            const pos = body_interface.getPosition(obj.body_id);
            const rot = body_interface.getRotation(obj.body_id);

            obj.position = Vec2.init(pos[0], pos[1]);
            obj.rotation = 2.0 * std.math.atan2(rot[2], rot[3]);
        }

        self.camera.position = self.objects.items[0].position;
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
