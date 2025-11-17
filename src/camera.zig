const Vec2 = @import("vec2.zig").Vec2;

pub const Camera = struct {
    const Self = @This();

    position: Vec2,
    zoom: f32,

    pub fn init(position: Vec2) Self {
        return .{
            .position = position,
            .zoom = 1.0,
        };
    }
};
