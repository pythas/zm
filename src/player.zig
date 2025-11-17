const std = @import("std");

const Vec2 = @import("vec2.zig").Vec2;

pub const Player = struct {
    const Self = @This();

    position: Vec2,
    velocity: Vec2,

    rotation: f32,
    angular_velocity: f32,

    thrust: f32,
    torque: f32,

    velocity_damping: f32,
    angular_damping: f32,

    pub fn init(
        position: Vec2,
        rotation: f32,
        thrust: f32,
        torque: f32,
    ) Self {
        return .{
            .position = position,
            .velocity = Vec2.init(0, 0),
            .rotation = rotation,
            .angular_velocity = 0,
            .thrust = thrust,
            .torque = torque,
            .velocity_damping = 0.1,
            .angular_damping = 0.9,
        };
    }

    pub fn update(self: *Self, dt: f32) void {
        self.position = self.position.add(self.velocity.mulScalar(dt));
        self.rotation = self.rotation + self.angular_velocity * dt;

        const v_factor = @max(0.0, 1.0 - self.velocity_damping * dt);
        const a_factor = @max(0.0, 1.0 - self.angular_damping * dt);

        self.velocity = self.velocity.mulScalar(v_factor);
        self.angular_velocity *= a_factor;
    }

    pub fn applyThrust(self: *Self, dt: f32, input_thrust: f32) void {
        const direction = Vec2.init(-@sin(self.rotation), @cos(self.rotation));
        const acceleration = direction.mulScalar(input_thrust * self.thrust);

        self.velocity = self.velocity.add(acceleration.mulScalar(dt));
    }

    pub fn applyTorque(self: *Self, dt: f32, input_torque: f32) void {
        const acceleration = input_torque * self.torque;

        self.angular_velocity = self.angular_velocity + acceleration * dt;
    }
};
