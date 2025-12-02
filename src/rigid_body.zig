const Vec2 = @import("vec2.zig").Vec2;

pub const RigidBody = struct {
    const Self = @This();

    // state
    position: Vec2,
    velocity: Vec2,
    rotation: f32,
    angular_velocity: f32,

    // physical
    mass: f32 = 1.0,
    moment_of_inertia: f32 = 1.0,
    center_of_mass: Vec2 = Vec2.init(0, 0),

    // damping
    linear_damping: f32 = 0.1,
    angular_damping: f32 = 0.9,

    pub fn init(position: Vec2, rotation: f32) Self {
        return .{
            .position = position,
            .velocity = Vec2.init(0, 0),
            .rotation = rotation,
            .angular_velocity = 0,
        };
    }

    pub fn update(self: *Self, dt: f32) void {
        // integrate position
        self.position = self.position.add(self.velocity.mulScalar(dt));
        self.rotation += self.angular_velocity * dt;

        // apply damping
        const v_factor = @max(0.0, 1.0 - self.linear_damping * dt);
        const a_factor = @max(0.0, 1.0 - self.angular_damping * dt);

        self.velocity = self.velocity.mulScalar(v_factor);
        self.angular_velocity *= a_factor;
    }

    pub fn addRelativeForce(self: *Self, dt: f32, force_local: Vec2) void {
        // rot 0 is up
        const cos = @cos(self.rotation);
        const sin = @sin(self.rotation);

        const world_x = force_local.x * cos - force_local.y * sin;
        const world_y = force_local.x * sin + force_local.y * cos;
        const force_world = Vec2.init(world_x, world_y);

        const accel = force_world.divScalar(self.mass);
        self.velocity = self.velocity.add(accel.mulScalar(dt));
    }

    pub fn addTorque(self: *Self, dt: f32, torque: f32) void {
        const angular_accel = torque / self.moment_of_inertia;
        self.angular_velocity += angular_accel * dt;
    }
};
