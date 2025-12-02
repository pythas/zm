const std = @import("std");
const color = @import("color.zig");
const math = std.math;
const zglfw = @import("zglfw");

const KeyboardState = @import("input.zig").KeyboardState;
const Map = @import("map.zig").Map;
const TileReference = @import("tile.zig").TileReference;
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

    last_left: zglfw.Action = .release,
    last_right: zglfw.Action = .release,

    pub fn init(allocator: std.mem.Allocator, map: Map) !Self {
        const camera = Camera.init(
            Vec2.init(0, 0),
        );

        const player = Player.init(
            allocator,
            Vec2.init(0, 0),
            0 * std.math.pi / 180.0,
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
    ) !void {
        const wh = window.getFramebufferSize();
        const mouse_pos = window.getCursorPos();
        const mouse_x: f32 = @floatCast(mouse_pos[0]);
        const mouse_y: f32 = @floatCast(mouse_pos[1]);
        const mouse_x_relative = mouse_x - @as(f32, @floatFromInt(wh[0])) / 2;
        const mouse_y_relative = mouse_y - @as(f32, @floatFromInt(wh[1])) / 2;

        const left_now = window.getMouseButton(.left);
        const right_now = window.getMouseButton(.right);

        const left_clicked = (left_now == .press and self.last_left == .release);
        const right_clicked = (right_now == .press and self.last_right == .release);

        // TODO : Move these
        const thrust = 1.0;
        const side_thrust = 0.8;
        const torque = 6.0;

        if (keyboard_state.isDown(.w)) {
            self.player.applyThrust(dt, thrust);
        }

        if (keyboard_state.isDown(.s)) {
            self.player.applyThrust(dt, -thrust);
        }

        if (keyboard_state.isDown(.a)) {
            self.player.applyTorque(dt, torque);
        }

        if (keyboard_state.isDown(.d)) {
            self.player.applyTorque(dt, -torque);
        }

        if (keyboard_state.isDown(.q)) {
            self.player.applySideThrust(dt, -side_thrust);
        }

        if (keyboard_state.isDown(.e)) {
            self.player.applySideThrust(dt, side_thrust);
        }

        if (left_clicked) {
            if (self.getTile(mouse_x_relative, mouse_y_relative)) |tile_ref| {
                if (tile_ref.getTile(&self.map)) |tile| {
                    if (tile.category != .Empty) {
                        try self.player.startTileAction(.Mine, tile_ref);
                    }
                }
            }
        }

        if (right_clicked) {
            // ...
        }

        // sync camera with player
        self.camera.position = self.player.position;

        try self.player.update(dt, &self.map);

        self.last_left = left_now;
        self.last_right = right_now;
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

    fn getTile(self: *Self, local_x: f32, local_y: f32) ?TileReference {
        const tile_size = @as(f32, @floatFromInt(Tile.tileSize));

        const world = self.camera.screenToWorld(
            .{
                .x = local_x,
                .y = local_y,
            },
            tile_size,
        );

        return self.map.getTileAtWorld(world, tile_size);
    }
};

pub fn scrollCallback(window: *zglfw.Window, xoffset: f64, yoffset: f64) callconv(.c) void {
    const world = zglfw.getWindowUserPointer(window, World) orelse return;

    world.onScroll(xoffset, yoffset);
}
