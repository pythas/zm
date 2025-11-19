const std = @import("std");

const Vec2 = @import("vec2.zig").Vec2;
const Tile = @import("tile.zig").Tile;

pub const Player = struct {
    const Self = @This();
    pub const playerWidth = 4;
    pub const playerHeight = 8;

    position: Vec2,
    velocity: Vec2,

    rotation: f32,
    angular_velocity: f32,

    thrust: f32,
    torque: f32,

    velocity_damping: f32,
    angular_damping: f32,

    tiles: [playerWidth][playerHeight]Tile,

    pub fn init(
        allocator: std.mem.Allocator,
        position: Vec2,
        rotation: f32,
        thrust: f32,
        torque: f32,
    ) Self {
        // const tiles: [playerWidth][playerHeight]Tile =
        //     .{.{Tile.init(.Hull, .Ships, 0)} ** playerHeight} ** playerWidth;

        var tiles: [playerWidth][playerHeight]Tile = undefined;

        tiles[0][0] = try Tile.init(allocator, .Hull, .Metal, .Ships, 0);
        tiles[1][0] = try Tile.init(allocator, .Hull, .Metal, .Ships, 33);
        tiles[2][0] = try Tile.init(allocator, .Hull, .Metal, .Ships, 33);
        tiles[3][0] = try Tile.init(allocator, .Hull, .Metal, .Ships, 1);
        tiles[0][1] = try Tile.init(allocator, .Hull, .Metal, .Ships, 32);
        tiles[0][2] = try Tile.init(allocator, .Hull, .Metal, .Ships, 32);
        tiles[0][3] = try Tile.init(allocator, .Hull, .Metal, .Ships, 32);
        tiles[0][4] = try Tile.init(allocator, .Hull, .Metal, .Ships, 32);
        tiles[0][5] = try Tile.init(allocator, .Hull, .Metal, .Ships, 32);
        tiles[0][6] = try Tile.init(allocator, .Hull, .Metal, .Ships, 32);
        tiles[1][1] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        tiles[1][2] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        tiles[1][3] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        tiles[1][4] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        tiles[1][5] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        tiles[1][6] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        tiles[2][1] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        tiles[2][2] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        tiles[2][3] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        tiles[2][4] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        tiles[2][5] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        tiles[2][6] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        tiles[3][1] = try Tile.init(allocator, .Hull, .Metal, .Ships, 34);
        tiles[3][2] = try Tile.init(allocator, .Hull, .Metal, .Ships, 34);
        tiles[3][3] = try Tile.init(allocator, .Hull, .Metal, .Ships, 34);
        tiles[3][4] = try Tile.init(allocator, .Hull, .Metal, .Ships, 34);
        tiles[3][5] = try Tile.init(allocator, .Hull, .Metal, .Ships, 34);
        tiles[3][6] = try Tile.init(allocator, .Hull, .Metal, .Ships, 34);
        tiles[0][6] = try Tile.init(allocator, .Hull, .Metal, .Ships, 2);
        tiles[1][6] = try Tile.init(allocator, .Hull, .Metal, .Ships, 35);
        tiles[2][6] = try Tile.init(allocator, .Hull, .Metal, .Ships, 35);
        tiles[3][6] = try Tile.init(allocator, .Hull, .Metal, .Ships, 3);

        return .{
            .position = position,
            .velocity = Vec2.init(0, 0),
            .rotation = rotation,
            .angular_velocity = 0,
            .thrust = thrust,
            .torque = torque,
            .velocity_damping = 0.1,
            .angular_damping = 0.9,
            .tiles = tiles,
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

    pub fn applySideThrust(self: *Self, dt: f32, input_strafe: f32) void {
        const right = Vec2.init(@cos(self.rotation), @sin(self.rotation));

        const acceleration = right.mulScalar(input_strafe * self.thrust);
        self.velocity = self.velocity.add(acceleration.mulScalar(dt));
    }
};
