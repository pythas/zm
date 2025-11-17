const Vec2 = @import("vec2.zig").Vec2;

pub const Ship = struct {
    const Self = @This();

    position: Vec2,
    direction: Vec2,

    pub fn init(position: Vec2, direction: Vec2) Self {
        return .{
            .position = position,
            .direction = direction,
        };
    }
};
