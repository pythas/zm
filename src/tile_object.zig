const std = @import("std");

const Tile = @import("tile.zig").Tile;
const Vec2 = @import("vec2.zig").Vec2;
const GpuTileGrid = @import("renderer/sprite_renderer.zig").GpuTileGrid;
const Direction = @import("tile.zig").Direction;
const Offset = @import("tile.zig").Offset;
const PartKind = @import("tile.zig").PartKind;
const TileReference = @import("tile.zig").TileReference;
const Physics = @import("box2d_physics.zig").Physics;
const BodyId = @import("box2d_physics.zig").BodyId;
const PhysicsTileData = @import("box2d_physics.zig").TileData;
const TileData = @import("tile.zig").TileData;
const InputState = @import("input.zig").InputState;
const PartStats = @import("ship.zig").PartStats;

pub const ShipCapabilities = struct {
    force_forward: f32 = 0.0,
    force_backward: f32 = 0.0,
    force_side_left: f32 = 0.0,
    force_side_right: f32 = 0.0,

    engine_imbalance_torque: f32 = 0.0,
    side_imbalance_torque: f32 = 0.0,

    rcs_torque: f32 = 0.0,
};

pub const ThrusterKind = enum {
    Main,
    Secondary,
};

pub const Thruster = struct {
    kind: ThrusterKind,
    x: f32,
    y: f32,
    direction: Direction,
    power: f32,
};

pub const ObjectType = enum {
    ShipPart,
    Asteroid,
    Debris,
};

pub const TileObject = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    id: u64,
    object_type: ObjectType = .Asteroid,

    body_id: BodyId = BodyId.invalid,
    position: Vec2,
    rotation: f32,

    width: usize,
    height: usize,
    radius: f32,
    tiles: []Tile,

    thrusters: std.ArrayList(Thruster),

    gpu_grid: ?GpuTileGrid = null,
    dirty: bool = false,
    physics_dirty: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        id: u64,
        width: usize,
        height: usize,
        position: Vec2,
        rotation: f32,
    ) !Self {
        const tiles = try allocator.alloc(Tile, width * height);
        @memset(tiles, try Tile.initEmpty());

        return .{
            .allocator = allocator,
            .id = id,
            .width = width,
            .height = height,
            .position = position,
            .rotation = rotation,
            .radius = 0.0,
            .tiles = tiles,
            .thrusters = std.ArrayList(Thruster).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.tiles);
        self.thrusters.deinit();
    }

    pub fn setTile(self: *Self, x: usize, y: usize, tile: Tile) void {
        if (x >= self.width or y >= self.height) {
            return;
        }

        self.tiles[y * self.width + x] = tile;
        self.dirty = true;
    }

    pub fn getTile(self: Self, x: usize, y: usize) ?*Tile {
        if (x >= self.width or y >= self.height) {
            return null;
        }

        const index = y * self.width + x;
        return &self.tiles[index];
    }

    pub fn setEmptyTile(self: *Self, x: usize, y: usize) void {
        const tile = self.getTile(x, y) orelse return;

        tile.* = try Tile.initEmpty();
        self.dirty = true;
    }

    pub fn getTileByPartKind(self: Self, part_kind: PartKind) ![]TileReference {
        var tile_refs = std.ArrayList(TileReference).init(self.allocator);
        errdefer tile_refs.deinit();

        for (self.tiles, 0..) |tile, i| {
            const current_part_kind = tile.getPartKind() orelse continue;

            if (current_part_kind == part_kind) {
                try tile_refs.append(.{
                    .object_id = self.id,
                    .tile_x = i % self.width,
                    .tile_y = i / self.width,
                });
            }
        }

        return tile_refs.toOwnedSlice();
    }

    pub fn getNeighbouringTile(
        self: Self,
        x: usize,
        y: usize,
        direction: Direction,
    ) ?*Tile {
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

    pub fn getTileCoordsAtWorldPos(self: Self, point: Vec2) ?struct {
        x: usize,
        y: usize,
    } {
        const dx = point.x - self.position.x;
        const dy = point.y - self.position.y;

        const cos_rot = @cos(self.rotation);
        const sin_rot = @sin(self.rotation);

        const local_x = dx * cos_rot + dy * sin_rot;
        const local_y = -dx * sin_rot + dy * cos_rot;

        const tile_size = 8.0;
        const half_width_units = @as(f32, @floatFromInt(self.width)) * (tile_size / 2.0);
        const half_height_units = @as(f32, @floatFromInt(self.height)) * (tile_size / 2.0);

        const grid_pos_x = local_x + half_width_units;
        const grid_pos_y = local_y + half_height_units;

        if (grid_pos_x < 0 or grid_pos_y < 0) {
            return null;
        }

        const grid_width_units = @as(f32, @floatFromInt(self.width)) * tile_size;
        const grid_height_units = @as(f32, @floatFromInt(self.height)) * tile_size;

        if (grid_pos_x >= grid_width_units or grid_pos_y >= grid_height_units) {
            return null;
        }

        return .{
            .x = @intFromFloat(@floor(grid_pos_x / tile_size)),
            .y = @intFromFloat(@floor(grid_pos_y / tile_size)),
        };
    }

    pub fn getTileWorldPos(self: Self, x: usize, y: usize) Vec2 {
        const tile_size = 8.0;

        const object_center_x = @as(f32, @floatFromInt(self.width)) * (tile_size / 2.0);
        const object_center_y = @as(f32, @floatFromInt(self.height)) * (tile_size / 2.0);

        const tile_center_x = (@as(f32, @floatFromInt(x)) * tile_size) + (tile_size / 2.0);
        const tile_center_y = (@as(f32, @floatFromInt(y)) * tile_size) + (tile_size / 2.0);

        const local_x = tile_center_x - object_center_x;
        const local_y = tile_center_y - object_center_y;

        const cos_rot = @cos(self.rotation);
        const sin_rot = @sin(self.rotation);

        const rot_x = local_x * cos_rot - local_y * sin_rot;
        const rot_y = local_x * sin_rot + local_y * cos_rot;

        return Vec2.init(self.position.x + rot_x, self.position.y + rot_y);
    }

    pub fn getDistanceToTile(self: Self, x: usize, y: usize, target: Vec2) f32 {
        const tile_world_pos = self.getTileWorldPos(x, y);

        const dx = target.x - tile_world_pos.x;
        const dy = target.y - tile_world_pos.y;

        return @sqrt(dx * dx + dy * dy);
    }

    pub fn getDistanceToTileSq(self: Self, x: usize, y: usize, target: Vec2) f32 {
        const tile_world_pos = self.getTileWorldPos(x, y);

        const dx = target.x - tile_world_pos.x;
        const dy = target.y - tile_world_pos.y;

        return dx * dx + dy * dy;
    }

    pub fn getTileAt(self: Self, point: Vec2) ?Tile {
        const coords = self.getTileCoordsAtWorldPos(point) orelse return null;

        return self.getTile(coords.x, coords.y).*;
    }

    pub fn applyInputThrust(self: *Self, physics: *Physics, input: InputState) void {
        if (!self.body_id.isValid()) {
            return;
        }

        const body_pos = physics.getPosition(self.body_id);
        const body_rot = physics.getRotation(self.body_id);

        const cos_rot = @cos(body_rot);
        const sin_rot = @sin(body_rot);

        for (self.thrusters.items) |thruster| {
            var should_fire = false;

            switch (thruster.direction) {
                .South => {
                    should_fire = (thruster.kind == .Main and input == .Forward) or
                        (thruster.kind == .Secondary and input == .SecondaryForward);
                },
                .North => {
                    should_fire = (thruster.kind == .Main and input == .Backward) or
                        (thruster.kind == .Secondary and input == .SecondaryBackward);
                },
                .West => {
                    should_fire = (thruster.kind == .Main and input == .Right) or
                        (thruster.kind == .Secondary and input == .SecondaryRight);
                },
                .East => {
                    should_fire = (thruster.kind == .Main and input == .Left) or
                        (thruster.kind == .Secondary and input == .SecondaryLeft);
                },
            }

            if (should_fire) {
                const local_dir = switch (thruster.direction) {
                    .North => Vec2.init(0.0, 1.0),
                    .South => Vec2.init(0.0, -1.0),
                    .East => Vec2.init(-1.0, 0.0),
                    .West => Vec2.init(1.0, 0.0),
                };

                const world_dir = Vec2.init(local_dir.x * cos_rot - local_dir.y * sin_rot, local_dir.x * sin_rot + local_dir.y * cos_rot);

                const force = Vec2.init(world_dir.x * thruster.power, world_dir.y * thruster.power);

                const local_pos = Vec2.init(thruster.x, thruster.y);
                const world_offset = Vec2.init(local_pos.x * cos_rot - local_pos.y * sin_rot, local_pos.x * sin_rot + local_pos.y * cos_rot);

                const apply_point = Vec2.init(body_pos.x + world_offset.x, body_pos.y + world_offset.y);

                physics.addForceAtPoint(self.body_id, force, apply_point, true);
            }
        }
    }

    pub fn recalculatePhysics(self: *Self, physics: *Physics) !void {
        self.physics_dirty = false;
        if (self.body_id.isValid()) {
            physics.destroyBody(self.body_id);
        }

        var physics_tiles = std.ArrayList(PhysicsTileData).init(self.allocator);
        defer physics_tiles.deinit();

        for (0..self.width) |x| {
            for (0..self.height) |y| {
                const tile = self.getTile(x, y) orelse continue;

                const density: f32 = switch (tile.data) {
                    .ShipPart => |ship_data| PartStats.getDensity(ship_data.kind),
                    .Terrain => 1.0,
                    .Empty => 0.0,
                };

                if (density == 0.0) {
                    continue;
                }

                const object_center_x = @as(f32, @floatFromInt(self.width)) * 4.0;
                const object_center_y = @as(f32, @floatFromInt(self.height)) * 4.0;
                const x_pos = @as(f32, @floatFromInt(x)) * 8.0 + 4.0 - object_center_x;
                const y_pos = @as(f32, @floatFromInt(y)) * 8.0 + 4.0 - object_center_y;

                try physics_tiles.append(PhysicsTileData{
                    .pos = Vec2.init(x_pos, y_pos),
                    .density = density,
                    .layer = if (self.object_type == .Debris) .Debris else .Default,
                });
            }
        }

        if (physics_tiles.items.len == 0) {
            if (self.body_id.isValid()) {
                physics.destroyBody(self.body_id);
                self.body_id = BodyId.invalid;
            }
            return;
        }

        var linear_velocity = Vec2.init(0, 0);
        var angular_velocity: f32 = 0.0;

        if (self.body_id.isValid()) {
            self.position = physics.getPosition(self.body_id);
            self.rotation = physics.getRotation(self.body_id);

            linear_velocity = physics.getLinearVelocity(self.body_id);
            angular_velocity = physics.getAngularVelocity(self.body_id);

            physics.destroyBody(self.body_id);
        }

        self.body_id = try physics.createBody(self.position, self.rotation);

        try physics.createTileShape(self.body_id, physics_tiles.items);

        physics.setLinearVelocity(self.body_id, linear_velocity);
        physics.setAngularVelocity(self.body_id, angular_velocity);

        try self.rebuildThrusters();
    }

    fn rebuildThrusters(self: *Self) !void {
        self.thrusters.clearRetainingCapacity();

        if (self.object_type != .ShipPart) {
            return;
        }

        for (0..self.width) |x| {
            for (0..self.height) |y| {
                const tile = self.getTile(x, y) orelse continue;
                const part_kind = tile.getPartKind() orelse continue;
                const tier = tile.getTier() orelse continue;

                const power: f32 = switch (part_kind) {
                    .Engine => PartStats.getEnginePower(tier),
                    else => continue,
                };

                const kind: ThrusterKind = switch (part_kind) {
                    .Engine => .Main,
                    else => continue,
                };

                const object_center_x = @as(f32, @floatFromInt(self.width)) * 4.0;
                const object_center_y = @as(f32, @floatFromInt(self.height)) * 4.0;
                const local_x = @as(f32, @floatFromInt(x)) * 8.0 + 4.0 - object_center_x;
                const local_y = @as(f32, @floatFromInt(y)) * 8.0 + 4.0 - object_center_y;

                try self.thrusters.append(.{
                    .kind = kind,
                    .x = local_x,
                    .y = local_y,
                    .direction = tile.rotation,
                    .power = power,
                });
            }
        }
    }
};
