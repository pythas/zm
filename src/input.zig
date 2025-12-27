const zglfw = @import("zglfw");

const Vec2 = @import("vec2.zig").Vec2;

pub const InputState = enum {
    forward,
    backward,
    left,
    right,
    secondary_forward,
    secondary_backward,
    secondary_left,
    secondary_right,
    rotate_cw,
    rotate_ccw,
};

pub const KeyboardState = struct {
    const Self = @This();

    window: *zglfw.Window,

    curr: u32 = 0,
    prev: u32 = 0,

    pub const Key = enum(u5) {
        w,
        a,
        s,
        d,
        q,
        e,
        r,
        f,
        o,
        up,
        down,
        left,
        right,
        space,
        left_shift,
        left_ctrl,
        f1,
    };

    pub fn init(window: *zglfw.Window) Self {
        return .{
            .window = window,
        };
    }

    pub fn update(self: *Self) void {
        self.prev = self.curr;
        self.curr = 0;

        if (self.window.getKey(.w) == .press) self.curr |= bit(.w);
        if (self.window.getKey(.a) == .press) self.curr |= bit(.a);
        if (self.window.getKey(.s) == .press) self.curr |= bit(.s);
        if (self.window.getKey(.d) == .press) self.curr |= bit(.d);
        if (self.window.getKey(.q) == .press) self.curr |= bit(.q);
        if (self.window.getKey(.e) == .press) self.curr |= bit(.e);
        if (self.window.getKey(.r) == .press) self.curr |= bit(.r);
        if (self.window.getKey(.f) == .press) self.curr |= bit(.f);
        if (self.window.getKey(.o) == .press) self.curr |= bit(.o);
        if (self.window.getKey(.up) == .press) self.curr |= bit(.up);
        if (self.window.getKey(.down) == .press) self.curr |= bit(.down);
        if (self.window.getKey(.left) == .press) self.curr |= bit(.left);
        if (self.window.getKey(.right) == .press) self.curr |= bit(.right);
        if (self.window.getKey(.space) == .press) self.curr |= bit(.space);
        if (self.window.getKey(.left_shift) == .press) self.curr |= bit(.left_shift);
        if (self.window.getKey(.left_control) == .press) self.curr |= bit(.left_ctrl);
        if (self.window.getKey(.F1) == .press) self.curr |= bit(.f1);
    }

    pub fn isDown(self: *const Self, k: Key) bool {
        return (self.curr & bit(k)) != 0;
    }
    pub fn wasDown(self: *const Self, k: Key) bool {
        return (self.prev & bit(k)) != 0;
    }

    pub fn isPressed(self: *const Self, k: Key) bool {
        return self.isDown(k) and !self.wasDown(k);
    }

    pub fn isReleased(self: *const Self, k: Key) bool {
        return !self.isDown(k) and self.wasDown(k);
    }

    inline fn bit(k: Key) u32 {
        return @as(u32, 1) << @intFromEnum(k);
    }
};

pub const MouseState = struct {
    const Self = @This();

    window: *zglfw.Window,

    x: f32 = 0.0,
    y: f32 = 0.0,

    last_left_action: zglfw.Action,
    last_right_action: zglfw.Action,

    is_left_clicked: bool = false,
    is_right_clicked: bool = false,

    is_left_down: bool = false,
    is_right_down: bool = false,

    pub fn init(window: *zglfw.Window) Self {
        const mouse_pos = window.getCursorPos();

        return .{
            .window = window,
            .x = @floatCast(mouse_pos[0]),
            .y = @floatCast(mouse_pos[1]),
            .last_left_action = window.getMouseButton(.left),
            .last_right_action = window.getMouseButton(.right),
        };
    }

    pub fn update(self: *Self) void {
        const left_action = self.window.getMouseButton(.left);
        self.is_left_clicked = left_action == .release and self.last_left_action == .press;
        self.is_left_down = left_action == .press;
        self.last_left_action = left_action;

        const right_action = self.window.getMouseButton(.right);
        self.is_right_clicked = right_action == .release and self.last_right_action == .press;
        self.is_right_down = right_action == .press;
        self.last_right_action = right_action;

        const mouse_pos = self.window.getCursorPos();
        self.x = @floatCast(mouse_pos[0]);
        self.y = @floatCast(mouse_pos[1]);
    }

    pub fn getRelativePosition(self: Self) Vec2 {
        const wh = self.window.getFramebufferSize();
        const x = self.x - @as(f32, @floatFromInt(wh[0])) / 2;
        const y = self.y - @as(f32, @floatFromInt(wh[1])) / 2;

        return Vec2.init(x, y);
    }
};
