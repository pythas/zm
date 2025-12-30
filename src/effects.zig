const Vec2 = @import("vec2.zig").Vec2;

pub const RailgunTrail = struct {
    start: Vec2,
    end: Vec2,
    lifetime: f32,
    max_lifetime: f32,
};
