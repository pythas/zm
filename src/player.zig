const std = @import("std");

const Vec2 = @import("vec2.zig").Vec2;
const Tile = @import("tile.zig").Tile;
const TileReference = @import("tile.zig").TileReference;
const Direction = @import("tile.zig").Direction;
const Offset = @import("tile.zig").Offset;
const Map = @import("map.zig").Map;
const RigidBody = @import("rigid_body.zig").RigidBody;

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

// TODO: Move me
pub const ShipStats = struct {
    force_forward: f32 = 0.0,
    force_backward: f32 = 0.0,
    force_side_left: f32 = 0.0,
    force_side_right: f32 = 0.0,

    engine_imbalance_torque: f32 = 0.0,
    side_imbalance_torque: f32 = 0.0,

    rcs_torque: f32 = 0.0,
};

pub const Player = struct {
    const Self = @This();
    pub const tileActionMineDuration = 10.0;
    const enginePower: f32 = 500.0;
    const rcsPower: f32 = 50.0;

    body: RigidBody,
    stats: ShipStats,

    tiles: [tilemapWidth][tilemapHeight]Tile,
    tile_actions: std.ArrayList(TileAction),

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

        var self = Self{
            .body = RigidBody.init(position, rotation),
            .stats = ShipStats{},
            .tiles = tiles,
            .tile_actions = std.ArrayList(TileAction).init(allocator),
        };

        self.recalculateStats();

        return self;
    }

    pub fn update(self: *Self, dt: f32, map: *Map) !void {
        self.body.update(dt);

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
    pub fn applyInputThrust(self: *Self, dt: f32, input: f32) void {
        var force: f32 = 0.0;
        var torque_penalty: f32 = 0.0;

        if (input > 0) {
            force = -self.stats.force_forward;
            torque_penalty = self.stats.engine_imbalance_torque;
        } else if (input < 0) {
            force = self.stats.force_backward;
        }

        self.body.addRelativeForce(dt, Vec2.init(0, force));

        if (torque_penalty != 0) {
            self.body.addTorque(dt, torque_penalty);
        }
    }

    pub fn applyTorque(self: *Self, dt: f32, input: f32) void {
        const torque = -input * self.stats.rcs_torque;

        self.body.addTorque(dt, torque);
    }

    pub fn applySideThrust(self: *Self, dt: f32, input: f32) void {
        var force: f32 = 0.0;
        var torque_penalty: f32 = 0.0;

        if (input < 0) {
            force = -self.stats.force_side_left;
            torque_penalty = self.stats.side_imbalance_torque;
        } else if (input > 0) {
            force = self.stats.force_side_right;
        }

        self.body.addRelativeForce(dt, Vec2.init(force, 0));

        if (torque_penalty != 0) {
            self.body.addTorque(dt, torque_penalty);
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

        self.body.mass = @max(1.0, total_mass);
        self.body.center_of_mass = weighted_pos.divScalar(self.body.mass);

        var inertia: f32 = 0.0;

        self.stats.force_forward = 0.0;
        self.stats.force_backward = 0.0;
        self.stats.force_side_left = 0.0;
        self.stats.force_side_right = 0.0;

        self.stats.rcs_torque = 0.0;
        self.stats.engine_imbalance_torque = 0.0;
        self.stats.side_imbalance_torque = 0.0;

        for (0..tilemapWidth) |x| {
            for (0..tilemapHeight) |y| {
                const tile = self.tiles[x][y];

                if (tile.category == .Empty) {
                    continue;
                }

                const pos = Vec2.init(@floatFromInt(x), @floatFromInt(y));
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
                        self.stats.force_forward += enginePower;
                        self.stats.engine_imbalance_torque += torque_arm * enginePower;
                    } else if (dir.y > 0.1) {
                        self.stats.force_backward += enginePower;
                    }

                    if (dir.x < -0.1) {
                        self.stats.force_side_left += enginePower;
                        self.stats.side_imbalance_torque += torque_arm * enginePower;
                    } else if (dir.x > 0.1) {
                        self.stats.force_side_right += enginePower;
                    }
                } else if (tile.category == .RCS) {
                    self.stats.rcs_torque += @abs(torque_arm * rcsPower);

                    if (dir.x < -0.1) self.stats.force_side_left += rcsPower;
                    if (dir.x > 0.1) self.stats.force_side_right += rcsPower;
                    if (dir.y < -0.1) self.stats.force_forward += rcsPower;
                    if (dir.y > 0.1) self.stats.force_backward += rcsPower;
                }
            }
        }

        self.body.moment_of_inertia = @max(1.0, inertia);
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
