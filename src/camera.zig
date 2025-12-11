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

    pub fn worldCenter(self: Camera) Vec2 {
        return self.position;
    }

    pub fn screenToWorld(self: Camera, local: Vec2) Vec2 {
        const center = self.worldCenter();

        return .{
            .x = center.x + local.x / self.zoom,
            .y = center.y + local.y / self.zoom,
        };
    }
};
