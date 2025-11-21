const zglfw = @import("zglfw");

pub const KeyboardState = struct {
    const Self = @This();

    window: *zglfw.Window,

    curr: u16 = 0,
    prev: u16 = 0,

    pub const Key = enum(u4) {
        w,
        a,
        s,
        d,
        q,
        e,
        r,
        f,
        up,
        down,
        left,
        right,
        space,
    };

    pub fn init(window: *zglfw.Window) Self {
        return .{
            .window = window,
        };
    }

    pub fn beginFrame(self: *Self) void {
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
        if (self.window.getKey(.up) == .press) self.curr |= bit(.up);
        if (self.window.getKey(.down) == .press) self.curr |= bit(.down);
        if (self.window.getKey(.left) == .press) self.curr |= bit(.left);
        if (self.window.getKey(.right) == .press) self.curr |= bit(.right);
        if (self.window.getKey(.space) == .press) self.curr |= bit(.space);
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

    inline fn bit(k: Key) u16 {
        return @as(u16, 1) << @intFromEnum(k);
    }
};
