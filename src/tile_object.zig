const std = @import("std");

const RigidBody = @import("rigid_body.zig").RigidBody;
const Tile = @import("tile.zig").Tile;
const Vec2 = @import("vec2.zig").Vec2;
const GpuTileGrid = @import("renderer/sprite_renderer.zig").GpuTileGrid;
const Direction = @import("tile.zig").Direction;
const Offset = @import("tile.zig").Offset;

pub const ShipCapabilities = struct {
    force_forward: f32 = 0.0,
    force_backward: f32 = 0.0,
    force_side_left: f32 = 0.0,
    force_side_right: f32 = 0.0,

    engine_imbalance_torque: f32 = 0.0,
    side_imbalance_torque: f32 = 0.0,

    rcs_torque: f32 = 0.0,
};

pub const TileObject = struct {
    const Self = @This();

    const enginePower: f32 = 5000.0;
    const rcsPower: f32 = 1000.0;

    allocator: std.mem.Allocator,

    body: RigidBody,

    width: usize,
    height: usize,
    radius: f32,
    tiles: []Tile,

    ship_stats: ?ShipCapabilities = null,

    gpu_grid: ?GpuTileGrid = null,
    dirty: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        width: usize,
        height: usize,
        position: Vec2,
        rotation: f32,
    ) !Self {
        const tiles = try allocator.alloc(Tile, width * height);
        @memset(tiles, try Tile.initEmpty(allocator));

        return .{
            .allocator = allocator,
            .body = RigidBody.init(position, rotation),
            .width = width,
            .height = height,
            .radius = 0.0,
            .tiles = tiles,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.tiles);
    }

    pub fn setTile(self: *Self, x: usize, y: usize, tile: Tile) void {
        if (x >= self.width or y >= self.height) {
            return;
        }

        self.tiles[y * self.width + x] = tile;
        self.dirty = true;
    }

    pub fn getTile(self: Self, x: usize, y: usize) ?Tile {
        if (x >= self.width or y >= self.height) {
            return null;
        }

        return self.tiles[y * self.width + x];
    }

    pub fn getNeighbouringTile(
        self: Self,
        x: usize,
        y: usize,
        direction: Direction,
    ) ?Tile {
        const delta: Offset = switch (direction) {
            .North => .{ .dx = 0, .dy = -1 },
            .East => .{ .dx = 1, .dy = 0 },
            .South => .{ .dx = 0, .dy = 1 },
            .West => .{ .dx = -1, .dy = 0 },
        };

        const nx = @as(isize, @intCast(x)) + delta.dx;
        const ny = @as(isize, @intCast(y)) + delta.dy;

        if (nx < 0 or ny < 0 or nx >= self.width or ny >= self.height) {
            return null;
        }

        return self.getTile(@intCast(nx), @intCast(ny));
    }

    pub fn applyInputThrust(self: *Self, dt: f32, input: f32) void {
        const stats = &(self.ship_stats orelse return);

        var force: f32 = 0.0;
        var torque_penalty: f32 = 0.0;

        if (input > 0) {
            force = -stats.force_forward;
            torque_penalty = stats.engine_imbalance_torque;
        } else if (input < 0) {
            force = stats.force_backward;
        }

        self.body.addRelativeForce(dt, Vec2.init(0, force));

        if (torque_penalty != 0) {
            self.body.addTorque(dt, torque_penalty);
        }
    }

    pub fn applyTorque(self: *Self, dt: f32, input: f32) void {
        const stats = &(self.ship_stats orelse return);

        const torque = -input * stats.rcs_torque;

        self.body.addTorque(dt, torque);
    }

    pub fn applySideThrust(self: *Self, dt: f32, input: f32) void {
        const stats = &(self.ship_stats orelse return);

        var force: f32 = 0.0;
        var torque_penalty: f32 = 0.0;

        if (input < 0) {
            force = -stats.force_side_left;
            torque_penalty = stats.side_imbalance_torque;
        } else if (input > 0) {
            force = stats.force_side_right;
        }

        self.body.addRelativeForce(dt, Vec2.init(force, 0));

        if (torque_penalty != 0) {
            self.body.addTorque(dt, torque_penalty);
        }
    }

    pub fn recalculatePhysics(self: *Self) void {
        var total_mass: f32 = 0.0;
        var weighted_pos = Vec2.init(0, 0);

        for (0..self.width) |x| {
            for (0..self.height) |y| {
                const tile = self.getTile(x, y) orelse continue;

                if (tile.category == .Empty) {
                    continue;
                }

                const mass: f32 = switch (tile.category) {
                    .Engine => 20.0,
                    .RCS => 5.0,
                    else => 10.0,
                };
                total_mass += mass;

                const pos = Vec2.init(@floatFromInt(x * 8 + 4), @floatFromInt(y * 8 + 4));
                weighted_pos = weighted_pos.add(pos.mulScalar(mass));
            }
        }

        self.body.mass = @max(1.0, total_mass);
        self.body.center_of_mass = weighted_pos.divScalar(self.body.mass);

        // calc radius
        var max_radius: f32 = 0.0;
        for (0..self.width) |x| {
            for (0..self.height) |y| {
                const tile = self.getTile(x, y) orelse continue;
                if (tile.category == .Empty) {
                    continue;
                }

                const pos = Vec2.init(@floatFromInt(x * 8 + 4), @floatFromInt(y * 8 + 4));
                const distance = pos.sub(self.body.center_of_mass).len() + 6.0;
                max_radius = @max(max_radius, distance);
            }
        }
        self.radius = max_radius;

        // ship calcs
        var stats = &(self.ship_stats orelse return);

        var inertia: f32 = 0.0;

        stats.force_forward = 0.0;
        stats.force_backward = 0.0;
        stats.force_side_left = 0.0;
        stats.force_side_right = 0.0;

        stats.rcs_torque = 0.0;
        stats.engine_imbalance_torque = 0.0;
        stats.side_imbalance_torque = 0.0;

        for (0..self.width) |x| {
            for (0..self.height) |y| {
                const tile = self.getTile(x, y) orelse continue;

                if (tile.category == .Empty) {
                    continue;
                }

                const pos = Vec2.init(@floatFromInt(x * 8 + 4), @floatFromInt(y * 8 + 4));
                const delta_com = pos.sub(self.body.center_of_mass);

                const mass: f32 = switch (tile.category) {
                    .Engine => 20.0,
                    .RCS => 5.0,
                    else => 10.0,
                };
                inertia += mass * delta_com.lenSquared();

                const dir = switch (tile.rotation) {
                    .North => Vec2.init(0, 1),
                    .South => Vec2.init(0, -1),
                    .East => Vec2.init(-1, 0),
                    .West => Vec2.init(1, 0),
                };

                const torque_arm = (delta_com.x * dir.y) - (delta_com.y * dir.x);

                if (tile.category == .Engine) {
                    if (dir.y < -0.1) {
                        stats.force_forward += enginePower;
                        stats.engine_imbalance_torque += torque_arm * enginePower;
                    } else if (dir.y > 0.1) {
                        stats.force_backward += enginePower;
                    }

                    if (dir.x < -0.1) {
                        stats.force_side_left += enginePower;
                        stats.side_imbalance_torque += torque_arm * enginePower;
                    } else if (dir.x > 0.1) {
                        stats.force_side_right += enginePower;
                    }
                } else if (tile.category == .RCS) {
                    stats.rcs_torque += @abs(torque_arm * rcsPower);

                    if (dir.x < -0.1) stats.force_side_left += rcsPower;
                    if (dir.x > 0.1) stats.force_side_right += rcsPower;
                    if (dir.y < -0.1) stats.force_forward += rcsPower;
                    if (dir.y > 0.1) stats.force_backward += rcsPower;
                }
            }
        }

        self.body.moment_of_inertia = @max(1.0, inertia);
    }
};
