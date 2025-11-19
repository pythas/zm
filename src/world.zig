const std = @import("std");
const color = @import("color.zig");
const math = std.math;
const zglfw = @import("zglfw");

const KeyboardState = @import("input.zig").KeyboardState;
const Map = @import("map.zig").Map;
const Chunk = @import("map.zig").Chunk;
const Player = @import("player.zig").Player;
const Camera = @import("camera.zig").Camera;
const Ship = @import("ship.zig").Ship;
const Vec2 = @import("vec2.zig").Vec2;
const Tile = @import("tile.zig").Tile;

pub const World = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    map: Map,
    camera: Camera,
    player: Player,

    pub fn init(allocator: std.mem.Allocator, map: Map) !Self {
        const camera = Camera.init(
            Vec2.init(0, 0),
        );

        const player = Player.init(
            allocator,
            Vec2.init(0, 0),
            0 * std.math.pi / 180.0,
            8.0,
            0.4,
        );

        return .{
            .allocator = allocator,
            .map = map,
            .camera = camera,
            .player = player,
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
    ) void {
        const wh = window.getFramebufferSize();
        const mouse_pos = window.getCursorPos();
        const mouse_x: f32 = @floatCast(mouse_pos[0]);
        const mouse_y: f32 = @floatCast(mouse_pos[1]);
        const mouse_x_relative = mouse_x - @as(f32, @floatFromInt(wh[0])) / 2;
        const mouse_y_relative = mouse_y - @as(f32, @floatFromInt(wh[1])) / 2;

        const left_button = window.getMouseButton(.left);
        const right_button = window.getMouseButton(.right);

        // TODO : Move these
        const thrust = 1.0;
        const side_thrust = 0.8;
        const torque = 6.0;

        if (keyboard_state.isDown(.w)) {
            self.player.applyThrust(dt, -thrust);
        }

        if (keyboard_state.isDown(.s)) {
            self.player.applyThrust(dt, thrust);
        }

        if (keyboard_state.isDown(.a)) {
            self.player.applyTorque(dt, -torque);
        }

        if (keyboard_state.isDown(.d)) {
            self.player.applyTorque(dt, torque);
        }

        if (keyboard_state.isDown(.q)) {
            self.player.applySideThrust(dt, -side_thrust);
        }

        if (keyboard_state.isDown(.e)) {
            self.player.applySideThrust(dt, side_thrust);
        }

        if (left_button == .press) {
            if (self.getTile(mouse_x_relative, mouse_y_relative)) |tile| {
                if (tile.category != .Empty) {
                    std.debug.print("tile hit: {d}\n", .{@intFromEnum(tile.category)});
                }
            }
        }

        if (right_button == .press) {
            // ...
        }

        // sync camera with player
        self.camera.position = self.player.position;

        self.player.update(dt);
    }

    fn tryMovePlayer(self: *Self, x: f32, y: f32) void {
        self.player.position.x += x;
        self.player.position.y += y;
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

    fn getTile(self: Self, x: f32, y: f32) ?Tile {
        const tile_size = @as(f32, @floatFromInt(Tile.tileSize));

        const camera_x = self.camera.position.x * tile_size;
        const camera_y = self.camera.position.y * tile_size;

        const world_x = camera_x + x;
        const world_y = camera_y + y;

        const chunk_size = @as(f32, @floatFromInt(Chunk.chunkSize)) * tile_size;

        const half_size = chunk_size / 2.0;

        for (self.map.chunks.items) |chunk| {
            const chunk_center_x =
                @as(f32, @floatFromInt(chunk.x)) * chunk_size;
            const chunk_center_y =
                @as(f32, @floatFromInt(chunk.y)) * chunk_size;

            const chunk_top = chunk_center_y - half_size;
            const chunk_right = chunk_center_x + half_size;
            const chunk_bottom = chunk_center_y + half_size;
            const chunk_left = chunk_center_x - half_size;

            if (world_x >= chunk_left and world_x <= chunk_right and
                world_y >= chunk_top and world_y <= chunk_bottom)
            {
                const relatve_x = world_x - chunk_left;
                const relatve_y = world_y - chunk_top;
                const tile_x: u32 = @intFromFloat(relatve_x / tile_size);
                const tile_y: u32 = @intFromFloat(relatve_y / tile_size);

                return chunk.tiles[tile_x][tile_y];
            }
        }

        return null;
    }
};

pub fn scrollCallback(window: *zglfw.Window, xoffset: f64, yoffset: f64) callconv(.c) void {
    const world = zglfw.getWindowUserPointer(window, World) orelse return;

    world.onScroll(xoffset, yoffset);
}
