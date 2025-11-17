const std = @import("std");
const color = @import("color.zig");
const math = std.math;
const zglfw = @import("zglfw");

const KeyboardState = @import("input.zig").KeyboardState;
const Map = @import("map.zig").Map;
const Player = @import("player.zig").Player;
const Camera = @import("camera.zig").Camera;
const Ship = @import("ship.zig").Ship;
const Vec2 = @import("vec2.zig").Vec2;

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
            Vec2.init(0, 0),
            180.0 * std.math.pi / 180.0,
            8.0,
            0.4,
        );

        // window.setScrollCallback(scrollCallback);

        return .{
            .allocator = allocator,
            .map = map,
            .camera = camera,
            .player = player,
        };
    }

    // fn scrollCallback(window: *zglfw.Window, xoffset: f64, yoffset: f64) callconv(.C) void {
    //     _ = window;
    //     _ = xoffset;
    //     _ = yoffset;
    //     // Handle scroll events here
    // }

    pub fn deinit(self: Self) void {
        _ = self;
    }

    pub fn update(
        self: *Self,
        dt: f32,
        keyboard_state: *const KeyboardState,
        window: *zglfw.Window,
    ) void {
        _ = window;
        // const mouse_pos = window.getCursorPos();
        // const mouse_x: f32 = @floatCast(mouse_pos[0]);
        // const mouse_y: f32 = @floatCast(mouse_pos[1]);
        // const left_button = window.getMouseButton(.left);
        // const right_button = window.getMouseButton(.right);

        const thrust = 1.0;
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

        // sync camera with player (for now)
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
};

pub fn scrollCallback(window: *zglfw.Window, xoffset: f64, yoffset: f64) callconv(.c) void {
    const world = zglfw.getWindowUserPointer(window, World) orelse return;

    world.onScroll(xoffset, yoffset);
}
