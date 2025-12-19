const std = @import("std");

pub const Vec2 = struct {
    const Self = @This();

    x: f32,
    y: f32,

    pub fn init(x: f32, y: f32) Vec2 {
        return .{ .x = x, .y = y };
    }

    pub fn add(self: Self, other: Self) Self {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn sub(self: Self, other: Self) Self {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }

    pub fn mulScalar(self: Self, scalar: f32) Self {
        return .{ .x = self.x * scalar, .y = self.y * scalar };
    }

    pub fn divScalar(self: Self, scalar: f32) Self {
        return .{ .x = self.x / scalar, .y = self.y / scalar };
    }

    pub fn length(self: Self) f32 {
        return std.math.sqrt(self.x * self.x + self.y * self.y);
    }

    pub fn lengthSq(self: Self) f32 {
        const l = self.length();

        return l * l;
    }

    pub fn normalize(self: Self) Self {
        const l = self.length();

        return .{
            .x = self.x / l,
            .y = self.y / l,
        };
    }

    pub fn dot(a: Self, b: Vec2) f32 {
        return a.x * b.x + a.y * b.y;
    }

    pub fn neg(self: Self) Self {
        return .{ .x = -self.x, .y = -self.y };
    }

    pub fn rotate(self: *Self, amount: f32) void {
        const old_x = self.x;
        self.x = self.x * @cos(amount) - self.y * @sin(amount);
        self.y = old_x * @sin(amount) + self.y * @cos(amount);
    }

    pub fn rotated(self: Self, amount: f32) Self {
        return .{
            .x = self.x * @cos(amount) - self.y * @sin(amount),
            .y = self.x * @sin(amount) + self.y * @cos(amount),
        };
    }

    pub fn lerp(self: Self, other: Self, t: f32) Self {
        return .{
            .x = self.x + (other.x - self.x) * t,
            .y = self.y + (other.y - self.y) * t,
        };
    }

    pub fn perpendicular(self: Self) Self {
        return .{ .x = self.y, .y = -self.x };
    }
};
