const std = @import("std");
const zglfw = @import("zglfw");
const Vec2 = @import("../vec2.zig").Vec2;
const KeyboardState = @import("../input.zig").KeyboardState;
const MouseState = @import("../input.zig").MouseState;

pub const GameAction = enum {
    move_forward,
    move_backward,
    move_left,
    move_right,
    rotate_cw,
    rotate_ccw,
    toggle_flight_assist,
    toggle_inventory,
    select_action_1,
    select_action_2,
    select_action_3,
    select_action_4,
    select_action_5,
    cycle_target,
    fire_secondary,
    fire_primary,
    open_tile_menu,
    cheat_repair,
};

pub const InputManager = struct {
    const Self = @This();

    keyboard: KeyboardState,
    mouse: MouseState,

    pub fn init(window: *zglfw.Window) Self {
        return .{
            .keyboard = KeyboardState.init(window),
            .mouse = MouseState.init(window),
        };
    }

    pub fn update(self: *Self) void {
        self.keyboard.update();
        self.mouse.update();
    }

    pub fn isActionDown(self: *const Self, action: GameAction) bool {
        return switch (action) {
            .move_forward => self.keyboard.isDown(.w) or self.keyboard.isDown(.up),
            .move_backward => self.keyboard.isDown(.s) or self.keyboard.isDown(.down),
            .move_left => self.keyboard.isDown(.a) or self.keyboard.isDown(.left),
            .move_right => self.keyboard.isDown(.d) or self.keyboard.isDown(.right),
            .rotate_cw => self.keyboard.isDown(.e),
            .rotate_ccw => self.keyboard.isDown(.q),
            .toggle_flight_assist => self.keyboard.isDown(.z),
            .toggle_inventory => self.keyboard.isDown(.o),
            .select_action_1 => self.keyboard.isDown(.one),
            .select_action_2 => self.keyboard.isDown(.two),
            .select_action_3 => self.keyboard.isDown(.three),
            .select_action_4 => self.keyboard.isDown(.four),
            .select_action_5 => self.keyboard.isDown(.five),
            .cycle_target => self.keyboard.isDown(.r),
            .fire_secondary => self.keyboard.isDown(.space),
            .fire_primary => self.mouse.is_left_down,
            .open_tile_menu => self.mouse.is_right_down,
            .cheat_repair => self.keyboard.isDown(.f1),
        };
    }

    pub fn isActionPressed(self: *const Self, action: GameAction) bool {
        return switch (action) {
            .move_forward => self.keyboard.isPressed(.w) or self.keyboard.isPressed(.up),
            .move_backward => self.keyboard.isPressed(.s) or self.keyboard.isPressed(.down),
            .move_left => self.keyboard.isPressed(.a) or self.keyboard.isPressed(.left),
            .move_right => self.keyboard.isPressed(.d) or self.keyboard.isPressed(.right),
            .rotate_cw => self.keyboard.isPressed(.e),
            .rotate_ccw => self.keyboard.isPressed(.q),
            .toggle_flight_assist => self.keyboard.isPressed(.z),
            .toggle_inventory => self.keyboard.isPressed(.o),
            .select_action_1 => self.keyboard.isPressed(.one),
            .select_action_2 => self.keyboard.isPressed(.two),
            .select_action_3 => self.keyboard.isPressed(.three),
            .select_action_4 => self.keyboard.isPressed(.four),
            .select_action_5 => self.keyboard.isPressed(.five),
            .cycle_target => self.keyboard.isPressed(.r),
            .fire_secondary => self.keyboard.isPressed(.space),
            .fire_primary => self.mouse.is_left_clicked, // This is technically released after pressed in current MouseState
            .open_tile_menu => self.mouse.is_right_clicked,
            .cheat_repair => self.keyboard.isPressed(.f1),
        };
    }

    pub fn getMouseWorldPos(self: *const Self, camera: anytype) Vec2 {
        const mouse_pos = self.mouse.getRelativePosition();
        return camera.screenToWorld(mouse_pos);
    }
};
