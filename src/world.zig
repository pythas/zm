const std = @import("std");
const color = @import("color.zig");
const math = std.math;
const zglfw = @import("zglfw");

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

    last_left: zglfw.Action = .release,
    last_right: zglfw.Action = .release,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const camera = Camera.init(
            Vec2.init(0, 0),
        );

        var objects = std.ArrayList(TileObject).init(allocator);

        var ship = try TileObject.init(allocator, 16, 16, Vec2.init(0.0, 0.0), 0);
        for (0..ship.width) |y| {
            for (0..ship.height) |x| {
                ship.tiles[y * ship.width + x] = try Tile.initEmpty(allocator);
            }
        }
        for (2..ship.width - 2) |y| {
            for (2..ship.height - 2) |x| {
                ship.tiles[y * ship.width + x] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
            }
        }
        ship.ship_stats = .{};
        ship.recalculatePhysics();
        try objects.append(ship);

        var asteroid = try TileObject.init(allocator, 16, 16, Vec2.init(0.0, -140.0), 1);
        for (0..asteroid.width) |y| {
            for (0..asteroid.height) |x| {
                asteroid.tiles[y * asteroid.width + x] = try Tile.initEmpty(allocator);
            }
        }
        for (2..asteroid.width - 2) |y| {
            for (2..asteroid.height - 2) |x| {
                asteroid.tiles[y * asteroid.width + x] = try Tile.init(allocator, .Hull, .Metal, .Ships, 34);
            }
        }
        asteroid.recalculatePhysics();
        try objects.append(asteroid);

        const player_controller = PlayerController.init(allocator, 0);

        return .{
            .allocator = allocator,
            .camera = camera,
            .objects = objects,
            .player_controller = player_controller,
        };
    }

    pub fn deinit(self: Self) void {
        _ = self;
    }

    pub fn update(
        self: *Self,
        dt: f32,
        keyboard_state: *const KeyboardState,
        window: *zglfw.Window,
    ) !void {
        _ = window;
        // const wh = window.getFramebufferSize();
        // const mouse_pos = window.getCursorPos();
        // const mouse_x: f32 = @floatCast(mouse_pos[0]);
        // const mouse_y: f32 = @floatCast(mouse_pos[1]);
        // const mouse_x_relative = mouse_x - @as(f32, @floatFromInt(wh[0])) / 2;
        // const mouse_y_relative = mouse_y - @as(f32, @floatFromInt(wh[1])) / 2;
        //
        // const left_now = window.getMouseButton(.left);
        // const right_now = window.getMouseButton(.right);
        //
        // const left_clicked = (left_now == .press and self.last_left == .release);
        // const right_clicked = (right_now == .press and self.last_right == .release);

        //
        // if (left_clicked) {
        //     if (self.getTile(mouse_x_relative, mouse_y_relative)) |tile_ref| {
        //         if (tile_ref.getTile(&self.map)) |tile| {
        //             if (tile.category != .Empty) {
        //                 try self.player_controller.startTileAction(.Mine, tile_ref);
        //             }
        //         }
        //     }
        // }
        //
        // if (right_clicked) {
        //     // ...
        // }

        self.player_controller.update(dt, self.objects.items, keyboard_state);
        self.updatePhysics(dt);

        // sync camera with player
        self.camera.position = self.objects.items[0].body.position;

        // self.last_left = left_now;
        // self.last_right = right_now;
    }

    pub fn updatePhysics(self: Self, dt: f32) void {
        for (self.objects.items) |*obj| {
            obj.body.update(dt);
        }

        for (0..self.objects.items.len) |i| {
            for (i + 1..self.objects.items.len) |j| {
                const obj_a = &self.objects.items[i];
                const obj_b = &self.objects.items[j];

                if (checkCollision(obj_a, obj_b)) {
                    // ...
                }
            }
        }
    }

    fn checkCollision(obj_a: *TileObject, obj_b: *TileObject) bool {
        // broad check
        const dx = obj_a.body.position.x - obj_b.body.position.x;
        const dy = obj_a.body.position.y - obj_b.body.position.y;
        const distance_sq = dx * dx + dy * dy;

        const combined_radius = obj_a.radius + obj_b.radius + 16.0; // 16px margin
        if (distance_sq > combined_radius * combined_radius) {
            return false;
        }

        const center_distance = @sqrt(distance_sq);
        const collision_threshold = (obj_a.radius + obj_b.radius) * 0.8;

        if (center_distance < collision_threshold) {
            return true;
        }

        return false;
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
