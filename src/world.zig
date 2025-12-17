const std = @import("std");
const math = std.math;
const zglfw = @import("zglfw");

const Physics = @import("box2d_physics.zig").Physics;
const KeyboardState = @import("input.zig").KeyboardState;
const MouseState = @import("input.zig").MouseState;
const PlayerController = @import("player.zig").PlayerController;
const Camera = @import("camera.zig").Camera;
const Vec2 = @import("vec2.zig").Vec2;
const Tile = @import("tile.zig").Tile;
const TileObject = @import("tile_object.zig").TileObject;
const ship_serialization = @import("ship_serialization.zig");

pub const World = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    camera: Camera,
    player_controller: PlayerController,

    next_object_id: u64 = 0,
    objects: std.ArrayList(TileObject),

    physics: Physics,

    pub fn init(allocator: std.mem.Allocator) !Self {
        var physics = try Physics.init(allocator);

        const camera = Camera.init(
            Vec2.init(0, 0),
        );

        const player_controller = PlayerController.init(allocator, 0);

        var self: Self = .{
            .allocator = allocator,
            .camera = camera,
            .objects = std.ArrayList(TileObject).init(allocator),
            .player_controller = player_controller,
            .physics = physics,
        };

        const ship_id = self.generateObjectId();
        var ship = ship_serialization.loadShip(allocator, ship_id, "ship.json") catch |err| switch (err) {
            error.FileNotFound => try TileObject.init(allocator, ship_id, 16, 16, Vec2.init(0, 0), 0),
            else => return err,
        };

        ship.object_type = .ShipPart;
        try ship.recalculatePhysics(&physics);
        try self.objects.append(ship);

        {
            var asteroid = try TileObject.init(allocator, self.generateObjectId(), 16, 16, Vec2.init(0.0, -300.0), 0);
            asteroid.object_type = .Asteroid;
            for (0..asteroid.width) |y| {
                for (0..asteroid.height) |x| {
                    // asteroid.tiles[y * asteroid.width + x] = try Tile.init(allocator, .Hull, .Metal, .Ships, 34);
                    asteroid.tiles[y * asteroid.width + x] = try Tile.init(
                        .{
                            .Terrain = .{
                                .base_material = .Rock,
                                .ores = .{
                                    .{
                                        .ore = .Iron,
                                        .richness = 1,
                                    },
                                    .{
                                        .ore = .None,
                                        .richness = 0,
                                    },
                                },
                            },
                        },
                        .{ .sheet = .Ships, .index = 34 },
                    );
                }
            }
            try asteroid.recalculatePhysics(&physics);
            try self.objects.append(asteroid);
        }

        {
            var asteroid = try TileObject.init(allocator, self.generateObjectId(), 16, 16, Vec2.init(-200.0, -300.0), 0);
            asteroid.object_type = .Asteroid;
            for (0..asteroid.width) |y| {
                for (0..asteroid.height) |x| {
                    asteroid.tiles[y * asteroid.width + x] = try Tile.init(
                        .{
                            .Terrain = .{
                                .base_material = .Rock,
                                .ores = .{
                                    .{
                                        .ore = .Iron,
                                        .richness = 1,
                                    },
                                    .{
                                        .ore = .None,
                                        .richness = 0,
                                    },
                                },
                            },
                        },
                        .{ .sheet = .Ships, .index = 34 },
                    );
                }
            }
            try asteroid.recalculatePhysics(&physics);
            try self.objects.append(asteroid);
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        for (self.objects.items) |*obj| {
            obj.deinit();
        }
        self.objects.deinit();
        self.physics.deinit();
        self.player_controller.deinit();
    }

    pub fn generateObjectId(self: *Self) u64 {
        const id = self.next_object_id;

        self.next_object_id += 1;

        return id;
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
        self.physics.update(dt);

        for (self.objects.items) |*obj| {
            if (!obj.body_id.isValid()) {
                continue;
            }
            const pos = self.physics.getPosition(obj.body_id);
            const rot = self.physics.getRotation(obj.body_id);

            obj.position = pos;
            obj.rotation = rot;
        }

        try self.player_controller.update(
            dt,
            self,
            keyboard_state,
            mouse_state,
        );

        for (self.objects.items) |*obj| {
            if (!obj.body_id.isValid()) {
                continue;
            }

            if (obj.dirty) {
                try obj.recalculatePhysics(&self.physics);
            }

            const pos = self.physics.getPosition(obj.body_id);
            const rot = self.physics.getRotation(obj.body_id);

            obj.position = pos;
            obj.rotation = rot;
        }

        if (self.objects.items.len > 0) {
            self.camera.position = self.objects.items[0].position;
        }
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
