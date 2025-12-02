const std = @import("std");

const Vec2 = @import("vec2.zig").Vec2;
const Tile = @import("tile.zig").Tile;
const TileReference = @import("tile.zig").TileReference;
const Direction = @import("tile.zig").Direction;
const Offset = @import("tile.zig").Offset;
const Map = @import("map.zig").Map;

const tilemapWidth = @import("tile.zig").tilemapWidth;
const tilemapHeight = @import("tile.zig").tilemapHeight;

pub const TileAction = struct {
    const Self = @This();

    pub const Kind = enum {
        Mine,
    };

    kind: Kind,
    tile_ref: TileReference,
    progress: f32,
    duration: f32,

    pub fn init(kind: Kind, tile_ref: TileReference, duration: f32) Self {
        return .{
            .kind = kind,
            .tile_ref = tile_ref,
            .progress = 0,
            .duration = duration,
        };
    }

    pub fn isActive(self: Self) bool {
        return self.progress < self.duration;
    }

    pub fn getProgress(self: Self) f32 {
        return @min(self.progress / self.duration, 1.0);
    }
};

pub const Player = struct {
    const Self = @This();
    pub const tileActionMineDuration = 10.0;
    const enginePower: f32 = 500.0;
    const rcsPower: f32 = 50.0;

    position: Vec2,
    velocity: Vec2,

    rotation: f32,
    angular_velocity: f32,

    velocity_damping: f32,
    angular_damping: f32,

    tiles: [tilemapWidth][tilemapHeight]Tile,

    tile_actions: std.ArrayList(TileAction),

    mass: f32 = 1.0,
    moment_of_inertia: f32 = 1.0,
    center_of_mass: Vec2 = Vec2.init(0, 0),

    force_forward: f32 = 0.0,
    force_backward: f32 = 0.0,

    force_side_left: f32 = 0.0,
    force_side_right: f32 = 0.0,
    engine_imbalance_torque: f32 = 0.0,
    side_imbalance_torque: f32 = 0.0,
    rcs_torque: f32 = 0.0,

    pub fn init(
        allocator: std.mem.Allocator,
        position: Vec2,
        rotation: f32,
    ) Self {
        // const tiles: [playerWidth][playerHeight]Tile =
        //     .{.{Tile.init(.Hull, .Ships, 0)} ** playerHeight} ** playerWidth;

        var tiles: [tilemapWidth][tilemapHeight]Tile = undefined;

        for (0..tilemapHeight) |y| {
            for (0..tilemapWidth) |x| {
                tiles[x][y] = try Tile.initEmpty(allocator);
            }
        }

        for (2..tilemapHeight - 2) |y| {
            for (2..tilemapWidth - 2) |x| {
                tiles[x][y] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
            }
        }

        // var t1 = try Tile.init(allocator, .Engine, .Metal, .Ships, 0);
        // t1.rotation = .South;
        // tiles[4][7] = t1;
        // var t2 = try Tile.init(allocator, .Engine, .Metal, .Ships, 0);
        // t2.rotation = .North;
        // tiles[2][0] = t2;

        var self = Self{
            .position = position,
            .velocity = Vec2.init(0, 0),
            .rotation = rotation,
            .angular_velocity = 0,
            .velocity_damping = 0.1,
            .angular_damping = 0.9,
            .tiles = tiles,
            .tile_actions = std.ArrayList(TileAction).init(allocator),
        };

        self.recalculateStats();

        return self;
    }

    pub fn update(self: *Self, dt: f32, map: *Map) !void {
        // Movement
        self.position = self.position.add(self.velocity.mulScalar(dt));
        self.rotation = self.rotation + self.angular_velocity * dt;

        const v_factor = @max(0.0, 1.0 - self.velocity_damping * dt);
        const a_factor = @max(0.0, 1.0 - self.angular_damping * dt);

        self.velocity = self.velocity.mulScalar(v_factor);
        self.angular_velocity *= a_factor;

        // Actions
        var i: usize = self.tile_actions.items.len;
        while (i > 0) {
            i -= 1;

            var tile_action = &self.tile_actions.items[i];
            tile_action.progress += dt;

            if (!tile_action.isActive()) {
                switch (tile_action.kind) {
                    .Mine => {
                        std.debug.print("mine tile: {d} {d}\n", .{ tile_action.tile_ref.tile_x, tile_action.tile_ref.tile_y });
                        try tile_action.tile_ref.mineTile(map);
                    },
                }

                _ = self.tile_actions.orderedRemove(i);
            }
        }
    }

    // Movement
    pub fn applyThrust(self: *Self, dt: f32, input_y: f32) void {
        var force_magnitude: f32 = 0.0;
        var induced_torque: f32 = 0.0;

        if (input_y > 0) {
            force_magnitude = self.force_forward;
            induced_torque = self.engine_imbalance_torque;
        } else if (input_y < 0) {
            force_magnitude = -self.force_backward;
        }

        const accel_magnitude = force_magnitude / self.mass;
        const dir = Vec2.init(@sin(self.rotation), -@cos(self.rotation));
        self.velocity = self.velocity.add(dir.mulScalar(accel_magnitude * dt));

        const angular_accel = induced_torque / self.moment_of_inertia;
        self.angular_velocity += angular_accel * dt;
    }

    pub fn applyTorque(self: *Self, dt: f32, input_x: f32) void {
        const torque = -input_x * self.rcs_torque;

        const angular_accel = torque / self.moment_of_inertia;
        self.angular_velocity += angular_accel * dt;
    }

    pub fn applySideThrust(self: *Self, dt: f32, input_strafe: f32) void {
        var force_magnitude: f32 = 0.0;
        var induced_torque: f32 = 0.0;

        if (input_strafe < 0) {
            force_magnitude = -self.force_side_left;
            induced_torque = self.side_imbalance_torque;
        } else if (input_strafe > 0) {
            force_magnitude = self.force_side_right;
        }

        const dir = Vec2.init(@cos(self.rotation), @sin(self.rotation));
        const accel_magnitude = force_magnitude / self.mass;

        self.velocity = self.velocity.add(dir.mulScalar(accel_magnitude * dt));

        if (induced_torque != 0.0) {
            const angular_accel = induced_torque / self.moment_of_inertia;
            self.angular_velocity += angular_accel * dt;
        }
    }

    pub fn recalculateStats(self: *Self) void {
        var total_mass: f32 = 0.0;
        var weighted_pos = Vec2.init(0, 0);

        for (0..tilemapWidth) |x| {
            for (0..tilemapHeight) |y| {
                const tile = self.tiles[x][y];
                if (tile.category == .Empty) continue;

                const mass: f32 = switch (tile.category) {
                    .Engine => 20.0,
                    .RCS => 5.0,
                    else => 10.0,
                };
                total_mass += mass;

                const pos = Vec2.init(@floatFromInt(x), @floatFromInt(y));
                weighted_pos = weighted_pos.add(pos.mulScalar(mass));
            }
        }

        self.mass = @max(1.0, total_mass);
        self.center_of_mass = weighted_pos.divScalar(self.mass);

        var inertia: f32 = 0.0;

        self.force_forward = 0.0;
        self.force_backward = 0.0;
        self.force_side_left = 0.0;
        self.force_side_right = 0.0;

        self.rcs_torque = 0.0;
        self.engine_imbalance_torque = 0.0;
        self.side_imbalance_torque = 0.0;

        for (0..tilemapWidth) |x| {
            for (0..tilemapHeight) |y| {
                const tile = self.tiles[x][y];

                if (tile.category == .Empty) {
                    continue;
                }

                const pos = Vec2.init(@floatFromInt(x), @floatFromInt(y));
                const delta_com = pos.sub(self.center_of_mass);

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
                        self.force_forward += enginePower;
                        self.engine_imbalance_torque += torque_arm * enginePower;
                    } else if (dir.y > 0.1) {
                        self.force_backward += enginePower;
                    }

                    if (dir.x < -0.1) {
                        self.force_side_left += enginePower;
                        self.side_imbalance_torque += torque_arm * enginePower;
                    } else if (dir.x > 0.1) {
                        self.force_side_right += enginePower;
                    }
                } else if (tile.category == .RCS) {
                    self.rcs_torque += @abs(torque_arm * rcsPower);

                    if (dir.x < -0.1) self.force_side_left += rcsPower;
                    if (dir.x > 0.1) self.force_side_right += rcsPower;
                    if (dir.y < -0.1) self.force_forward += rcsPower;
                    if (dir.y > 0.1) self.force_backward += rcsPower;
                }
            }
        }
        self.moment_of_inertia = @max(1.0, inertia);
    }

    // Actions
    pub fn startTileAction(self: *Self, kind: TileAction.Kind, tile_ref: TileReference) !void {
        try self.tile_actions.append(TileAction.init(
            kind,
            tile_ref,
            tileActionMineDuration,
        ));
    }

    // Stuff
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

        if (nx < 0 or ny < 0 or nx >= tilemapWidth or ny >= tilemapHeight) {
            return null;
        }

        return self.tiles[@intCast(nx)][@intCast(ny)];
    }
};
