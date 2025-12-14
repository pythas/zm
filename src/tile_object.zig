const std = @import("std");
const zphy = @import("zphysics");
const zm = @import("zmath");

const Tile = @import("tile.zig").Tile;
const Vec2 = @import("vec2.zig").Vec2;
const GpuTileGrid = @import("renderer/sprite_renderer.zig").GpuTileGrid;
const Direction = @import("tile.zig").Direction;
const Offset = @import("tile.zig").Offset;
const TileCategory = @import("tile.zig").TileCategory;
const TileReference = @import("tile.zig").TileReference;
const Physics = @import("physics.zig").Physics;
const InputState = @import("input.zig").InputState;

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

pub const TileObject = struct {
    const Self = @This();

    const enginePower: f32 = 200000.0;
    const rcsPower: f32 = 200000.0;

    allocator: std.mem.Allocator,

    id: u64,

    body_id: zphy.BodyId = .invalid,
    position: Vec2,
    rotation: f32,

    width: usize,
    height: usize,
    radius: f32,
    tiles: []Tile,

    ship_stats: ?ShipCapabilities = null,
    thrusters: std.ArrayList(Thruster),

    gpu_grid: ?GpuTileGrid = null,
    dirty: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        id: u64,
        width: usize,
        height: usize,
        position: Vec2,
        rotation: f32,
    ) !Self {
        const tiles = try allocator.alloc(Tile, width * height);
        @memset(tiles, try Tile.initEmpty(allocator));

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

        return &self.tiles[y * self.width + x];
    }

    pub fn setEmptyTile(self: *Self, x: usize, y: usize) void {
        var tile = self.getTile(x, y) orelse return;

        tile.category = .Empty;
        self.dirty = true;

        // TODO: Create a tile.setEmpty that sets all props
    }

    pub fn getTileByCategory(self: Self, category: TileCategory) ![]TileReference {
        var tile_refs = std.ArrayList(TileReference).init(self.allocator);
        errdefer tile_refs.deinit();

        for (self.tiles, 0..) |tile, i| {
            if (tile.category == category) {
                try tile_refs.append(.{
                    .object_id = self.id,
                    .tile_x = i % self.width,
                    .tile_y = i / self.height,
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

        const cos = @cos(self.rotation);
        const sin = @sin(self.rotation);

        const local_x = dx * cos + dy * sin;
        const local_y = -dx * sin + dy * cos;

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

        const cos = @cos(self.rotation);
        const sin = @sin(self.rotation);

        const rot_x = local_x * cos - local_y * sin;
        const rot_y = local_x * sin + local_y * cos;

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

        return self.getTile(coords.x, coords.y);
    }

    pub fn applyInputThrust(self: *Self, physics: *Physics, input: InputState) void {
        if (self.body_id == .invalid) {
            return;
        }

        const body_interface = physics.physics_system.getBodyInterfaceMut();

        body_interface.activate(self.body_id);

        const pos_arr = body_interface.getPosition(self.body_id);
        const rot_arr = body_interface.getRotation(self.body_id);

        const v_body_pos = zm.loadArr3(pos_arr);
        const q_rotation = zm.loadArr4(rot_arr);
        const m_rotation = zm.matFromQuat(q_rotation);

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
                const v_local_dir = switch (thruster.direction) {
                    .North => zm.f32x4(0.0, 1.0, 0.0, 0.0),
                    .South => zm.f32x4(0.0, -1.0, 0.0, 0.0),
                    .East => zm.f32x4(-1.0, 0.0, 0.0, 0.0),
                    .West => zm.f32x4(1.0, 0.0, 0.0, 0.0),
                };

                const v_world_dir = zm.mul(v_local_dir, m_rotation);
                const v_force = v_world_dir * zm.f32x4s(thruster.power);
                const v_local_pos = zm.f32x4(thruster.x, thruster.y, 0.0, 0.0);
                const v_world_offset = zm.mul(v_local_pos, m_rotation);
                const v_apply_point = v_body_pos + v_world_offset;

                var final_force: [3]f32 = undefined;
                var final_point: [3]f32 = undefined;

                zm.storeArr3(&final_force, v_force);
                zm.storeArr3(&final_point, v_apply_point);

                body_interface.addForceAtPosition(self.body_id, final_force, final_point);
            }
        }
    }

    pub fn recalculatePhysics(self: *Self, physics: *Physics) !void {
        const body_interface = physics.physics_system.getBodyInterfaceMut();
        if (self.body_id != .invalid) {
            body_interface.removeBody(self.body_id);
            body_interface.destroyBody(self.body_id);
            self.body_id = .invalid;
        }

        const compound_settings = try zphy.CompoundShapeSettings.createStatic();
        defer compound_settings.asShapeSettings().release();

        for (0..self.width) |x| {
            for (0..self.height) |y| {
                const tile = self.getTile(x, y) orelse continue;
                if (tile.category == .Empty) {
                    continue;
                }

                const box_settings = try zphy.BoxShapeSettings.create(.{ 4.0, 4.0, 1.0 });
                defer box_settings.asShapeSettings().release();

                box_settings.asConvexShapeSettings().setDensity(switch (tile.category) {
                    .Engine => 2.0,
                    .RCS => 0.5,
                    .Hull => 1.0,
                    .Laser => 1.0,
                    else => 1000.0,
                });

                const object_center_x = @as(f32, @floatFromInt(self.width)) * 4.0;
                const object_center_y = @as(f32, @floatFromInt(self.height)) * 4.0;
                const x_pos = @as(f32, @floatFromInt(x)) * 8.0 + 4.0 - object_center_x;
                const y_pos = @as(f32, @floatFromInt(y)) * 8.0 + 4.0 - object_center_y;

                compound_settings.addShape(
                    .{ x_pos, y_pos, 0.0 },
                    .{ 0, 0, 0, 1 },
                    box_settings.asShapeSettings(),
                    0, // NOTE: userData
                );
            }
        }

        const shape = try compound_settings.asShapeSettings().createShape();
        defer shape.release();

        const mask: u32 = 1 + 2 + 4 + 32; // TRANSLATION_X + TRANSLATION_Y + TRANSLATION_Z + ROTATION_Z = 39
        const allowed_dofs = @as(*const zphy.AllowedDOFs, @ptrCast(&mask)).*;

        const q_rotation = zm.quatFromAxisAngle(zm.f32x4(0.0, 0.0, 1.0, 0.0), self.rotation);

        var rot_arr: [4]f32 = undefined;
        zm.storeArr4(&rot_arr, q_rotation);

        const body_settings = zphy.BodyCreationSettings{
            .shape = shape,
            .position = .{ self.position.x, self.position.y, 0.0, 0.0 },
            .rotation = rot_arr,
            .motion_type = .dynamic,
            .object_layer = 1,
            .allowed_DOFs = allowed_dofs,
        };

        self.body_id = try body_interface.createAndAddBody(body_settings, .activate);

        physics.physics_system.optimizeBroadPhase();

        // ship
        self.thrusters.clearRetainingCapacity();

        for (0..self.width) |x| {
            for (0..self.height) |y| {
                const tile = self.getTile(x, y) orelse continue;

                if (tile.category == .Empty) {
                    continue;
                }

                const power = switch (tile.category) {
                    .Engine => enginePower,
                    .RCS => rcsPower,
                    else => 0.0,
                };

                const kind: ThrusterKind = switch (tile.category) {
                    .Engine => .Main,
                    .RCS => .Secondary,
                    else => .Main,
                };

                if (power == 0.0) {
                    continue;
                }

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
