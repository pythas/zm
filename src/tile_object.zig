const std = @import("std");

const Tile = @import("tile.zig").Tile;
const Vec2 = @import("vec2.zig").Vec2;
const GpuTileGrid = @import("renderer/sprite_renderer.zig").GpuTileGrid;
const Direction = @import("tile.zig").Direction;
const Directions = @import("tile.zig").Directions;
const Offset = @import("tile.zig").Offset;
const PartKind = @import("tile.zig").PartKind;
const PartModule = @import("tile.zig").PartModule;
const TileReference = @import("tile.zig").TileReference;
const TileCoords = @import("tile.zig").TileCoords;
const Physics = @import("box2d_physics.zig").Physics;
const BodyId = @import("box2d_physics.zig").BodyId;
const PhysicsTileData = @import("box2d_physics.zig").TileData;
const TileData = @import("tile.zig").TileData;
const InputState = @import("input.zig").InputState;
const PartStats = @import("ship.zig").PartStats;
const TileType = @import("tile.zig").TileType;
const Item = @import("inventory.zig").Item;
const Inventory = @import("inventory.zig").Inventory;
const Resource = @import("resource.zig").Resource;
const ResearchManager = @import("research.zig").ResearchManager;
const rng = @import("rng.zig");

pub const ThrusterKind = enum {
    main,
    secondary,
};

pub const Thruster = struct {
    kind: ThrusterKind,
    x: f32,
    y: f32,
    direction: Direction,
    power: f32,
    current_visual_power: f32 = 0.0,
};

pub const ObjectType = enum {
    ship_part,
    asteroid,
    debris,
    enemy_drone,
};

pub const TileObject = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    id: u64,
    object_type: ObjectType = .asteroid,

    body_id: BodyId = BodyId.invalid,
    position: Vec2,
    rotation: f32,

    width: usize,
    height: usize,
    radius: f32,
    tiles: []Tile,

    inventories: std.AutoHashMap(usize, Inventory),

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
            .inventories = std.AutoHashMap(usize, Inventory).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.tiles);
        self.thrusters.deinit();

        var it = self.inventories.valueIterator();
        while (it.next()) |inv| {
            inv.deinit();
        }
        self.inventories.deinit();
    }

    pub fn repairAll(self: *Self) void {
        for (self.tiles, 0..) |tile, i| {
            if (tile.data == .ship_part) {
                self.tiles[i].data.ship_part.health = 100.0; // TODO: Load from PartStats
            }
        }
        self.dirty = true;
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

    pub fn getTilesByPartKind(self: Self, part_kind: PartKind) ![]TileReference {
        var tile_refs = std.ArrayList(TileReference).init(self.allocator);
        errdefer tile_refs.deinit();

        for (self.tiles, 0..) |tile, i| {
            const current_part_kind = tile.getPartKind() orelse continue;

            var match = current_part_kind == part_kind;

            // also check smart core modules
            if (!match and current_part_kind == .smart_core) {
                if (tile.data == .ship_part) {
                    const modules = tile.data.ship_part.modules;
                    match = switch (part_kind) {
                        .chemical_thruster => PartModule.has(modules, PartModule.thruster),
                        .laser => PartModule.has(modules, PartModule.laser),
                        .railgun => PartModule.has(modules, PartModule.railgun),
                        .storage => PartModule.has(modules, PartModule.storage),
                        .reactor => PartModule.has(modules, PartModule.reactor),
                        else => false,
                    };
                }
            }

            if (match) {
                try tile_refs.append(.{
                    .object_id = self.id,
                    .tile_x = i % self.width,
                    .tile_y = i / self.width,
                });
            }
        }

        return tile_refs.toOwnedSlice();
    }

    pub fn getClosestTileByPartKind(
        self: Self,
        part_kind: PartKind,
        target: Vec2,
    ) ![]TileReference {
        const tile_refs = self.getTilesByPartKind(part_kind);

        var min: ?f32 = null;
        var closest_tile_ref: ?TileReference = null;

        for (tile_refs) |tile_ref| {
            const d = self.getDistanceToTile(tile_ref.x, tile_ref.y, target);

            if (min == null or d < min) {
                min = d;
                closest_tile_ref = tile_ref;
            }
        }

        return closest_tile_ref;
    }

    pub fn getTilesByPartKindSortedByDist(
        self: Self,
        part_kind: PartKind,
        target: Vec2,
    ) ![]TileReference {
        const tile_refs = try self.getTilesByPartKind(part_kind);

        const SortContext = struct {
            self: Self,
            target: Vec2,

            pub fn lessThan(ctx: @This(), lhs: TileReference, rhs: TileReference) bool {
                const d1 = ctx.self.getDistanceToTile(lhs.tile_x, lhs.tile_y, ctx.target);
                const d2 = ctx.self.getDistanceToTile(rhs.tile_x, rhs.tile_y, ctx.target);
                return d1 < d2;
            }
        };

        std.mem.sortUnstable(TileReference, tile_refs, SortContext{ .self = self, .target = target }, SortContext.lessThan);

        return tile_refs;
    }

    pub fn getNeighbouringTile(
        self: Self,
        x: usize,
        y: usize,
        direction: Direction,
    ) ?*Tile {
        const delta: Offset = switch (direction) {
            .north => .{ .dx = 0, .dy = -1 },
            .east => .{ .dx = 1, .dy = 0 },
            .south => .{ .dx = 0, .dy = 1 },
            .west => .{ .dx = -1, .dy = 0 },
        };

        const nx = @as(isize, @intCast(x)) + delta.dx;
        const ny = @as(isize, @intCast(y)) + delta.dy;

        if (nx < 0 or ny < 0 or nx >= self.width or ny >= self.height) {
            return null;
        }

        return self.getTile(@intCast(nx), @intCast(ny));
    }

    pub fn getNeighborMask(self: Self, x: usize, y: usize) u8 {
        var mask: u8 = 0;
        const tile = self.getTile(x, y) orelse return 0;
        const tile_type = std.meta.activeTag(tile.data);

        const Neighbor = struct {
            dir: Direction,
            bit: u3,
        };
        const neighbors = [4]Neighbor{
            Neighbor{ .dir = .north, .bit = 0 },
            Neighbor{ .dir = .east, .bit = 1 },
            Neighbor{ .dir = .south, .bit = 2 },
            Neighbor{ .dir = .west, .bit = 3 },
        };

        for (neighbors) |n| {
            if (self.getNeighbouringTile(x, y, n.dir)) |neighbor| {
                if (std.meta.activeTag(neighbor.data) != tile_type) {
                    continue;
                }

                mask |= @as(u8, 1) << n.bit;
            }
        }

        return mask;
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

    // inventory
    pub fn initInventories(self: *Self) !void {
        const tile_refs = try self.getTilesByPartKind(.storage);
        defer self.allocator.free(tile_refs);

        for (tile_refs) |tile_ref| {
            const tile = self.getTile(tile_ref.tile_x, tile_ref.tile_y) orelse continue;
            const part = tile.getShipPart() orelse continue;
            if (PartStats.isBroken(part)) continue;

            _ = try self.addInventory(tile_ref.tile_x, tile_ref.tile_y, PartStats.getStorageSlotLimit(part.tier));
        }
    }

    pub fn getInventory(self: *Self, x: usize, y: usize) ?*Inventory {
        if (x >= self.width or y >= self.height) {
            return null;
        }

        const index = y * self.width + x;
        return self.inventories.getPtr(index);
    }

    pub fn addInventory(self: *Self, x: usize, y: usize, slot_limit: u32) !*Inventory {
        const index = y * self.width + x;

        if (self.inventories.getPtr(index)) |inventory| {
            try inventory.resize(slot_limit);
            return inventory;
        }

        const inventory = try Inventory.init(self.allocator, slot_limit);
        try self.inventories.put(index, inventory);

        return self.inventories.getPtr(index).?;
    }

    pub fn removeInventory(self: *Self, x: usize, y: usize) void {
        const index = y * self.width + x;

        if (self.inventories.fetchRemove(index)) |kv| {
            var inv = kv.value;
            inv.deinit();
        }
    }

    pub fn addItemToInventory(
        self: *Self,
        item: Item,
        amount: u32,
        from_position: Vec2,
    ) !u32 {
        const storage_list = try self.getTilesByPartKindSortedByDist(.storage, from_position);
        defer self.allocator.free(storage_list);

        var remaining = amount;

        for (storage_list) |storage| {
            const inventory = self.getInventory(
                storage.tile_x,
                storage.tile_y,
            ) orelse continue;

            const result = try inventory.add(item, remaining);
            remaining = @intCast(result.remaining);

            if (remaining == 0) {
                break;
            }
        }

        return remaining;
    }

    pub fn getInventoryCountByItem(self: *Self, item: Item) u32 {
        var count: u32 = 0;

        var it = self.inventories.valueIterator();
        while (it.next()) |inv| {
            for (inv.stacks.items) |stack| {
                if (stack.item.eql(item)) {
                    count += stack.amount;
                }
            }
        }

        return count;
    }

    pub fn removeNumberOfItemsFromInventory(self: *Self, item: Item, amount: u32) void {
        var remaining = amount;

        var it = self.inventories.valueIterator();
        while (it.next()) |inv| {
            for (inv.stacks.items) |*stack| {
                if (remaining == 0) {
                    return;
                }

                if (stack.item.eql(item) and stack.amount > 0) {
                    const take = @min(stack.amount, remaining);

                    stack.amount -= take;
                    remaining -= take;

                    if (stack.amount == 0) {
                        stack.item = .none;
                    }
                }
            }
        }
    }

    // physics
    pub fn applyInputTorque(self: *Self, physics: *Physics, input: InputState) void {
        if (!self.body_id.isValid()) {
            return;
        }

        const torque_power: f32 = 1_000_000.0;

        switch (input) {
            .rotate_cw => {
                physics.addTorque(self.body_id, torque_power, true);
            },
            .rotate_ccw => {
                physics.addTorque(self.body_id, -torque_power, true);
            },
            else => {},
        }
    }

    pub fn applyInputThrust(self: *Self, physics: *Physics, input: InputState) void {
        if (!self.body_id.isValid()) {
            return;
        }

        const body_pos = physics.getPosition(self.body_id);
        const body_rot = physics.getRotation(self.body_id);

        const cos_rot = @cos(body_rot);
        const sin_rot = @sin(body_rot);

        for (self.thrusters.items) |*thruster| {
            var should_fire = false;

            switch (thruster.direction) {
                .south => {
                    should_fire = (thruster.kind == .main and input == .forward) or
                        (thruster.kind == .secondary and input == .secondary_forward);
                },
                .north => {
                    should_fire = (thruster.kind == .main and input == .backward) or
                        (thruster.kind == .secondary and input == .secondary_backward);
                },
                .west => {
                    should_fire = (thruster.kind == .main and input == .right) or
                        (thruster.kind == .secondary and input == .secondary_right);
                },
                .east => {
                    should_fire = (thruster.kind == .main and input == .left) or
                        (thruster.kind == .secondary and input == .secondary_left);
                },
            }

            if (should_fire) {
                thruster.current_visual_power = thruster.power;

                const local_dir = switch (thruster.direction) {
                    .north => Vec2.init(0.0, 1.0),
                    .south => Vec2.init(0.0, -1.0),
                    .east => Vec2.init(-1.0, 0.0),
                    .west => Vec2.init(1.0, 0.0),
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

    pub fn stabilize(self: *Self, physics: *Physics, linear: bool) void {
        if (!self.body_id.isValid()) return;

        if (linear) {
            const vel = physics.getLinearVelocity(self.body_id);

            if (vel.lengthSq() > 0.1) {
                const rot = physics.getRotation(self.body_id);
                const cos = @cos(-rot);
                const sin = @sin(-rot);

                // transform velocity to local space
                const local_vel = Vec2.init(
                    vel.x * cos - vel.y * sin,
                    vel.x * sin + vel.y * cos,
                );

                const threshold = 0.2;

                if (local_vel.y > threshold) self.applyInputThrust(physics, .forward);
                if (local_vel.y < -threshold) self.applyInputThrust(physics, .backward);
                if (local_vel.x > threshold) self.applyInputThrust(physics, .left);
                if (local_vel.x < -threshold) self.applyInputThrust(physics, .right);
            }
        }
    }

    pub fn updateThrusterVisuals(self: *Self, dt: f32) void {
        for (self.thrusters.items) |*thruster| {
            if (thruster.current_visual_power > 0) {
                thruster.current_visual_power -= thruster.current_visual_power * 10.0 * dt;

                if (thruster.current_visual_power < 0.1) {
                    thruster.current_visual_power = 0;
                }
            }
        }
    }

    pub fn checkSplit(
        self: *Self,
        allocator: std.mem.Allocator,
        id_gen_ctx: anytype,
        id_gen_fn: fn (@TypeOf(id_gen_ctx)) u64,
    ) !?std.ArrayList(TileObject) {
        // Find connected components
        const Component = struct {
            tiles: std.ArrayList(TileCoords),
            min_x: usize,
            min_y: usize,
            max_x: usize,
            max_y: usize,
        };

        var components = std.ArrayList(Component).init(allocator);
        defer {
            for (components.items) |*c| c.tiles.deinit();
            components.deinit();
        }

        const visited = try allocator.alloc(bool, self.width * self.height);
        defer allocator.free(visited);
        @memset(visited, false);

        for (0..self.height) |y| {
            for (0..self.width) |x| {
                if (visited[y * self.width + x]) continue;

                const tile = self.getTile(x, y) orelse continue;
                if (tile.data == .empty) continue;

                var component = Component{
                    .tiles = std.ArrayList(TileCoords).init(allocator),
                    .min_x = x,
                    .min_y = y,
                    .max_x = x,
                    .max_y = y,
                };

                // flood fill
                var queue = std.ArrayList(TileCoords).init(allocator);
                defer queue.deinit();

                try queue.append(.{ .x = x, .y = y });
                visited[y * self.width + x] = true;

                while (queue.items.len > 0) {
                    const curr = queue.pop().?;
                    try component.tiles.append(curr);

                    component.min_x = @min(component.min_x, curr.x);
                    component.min_y = @min(component.min_y, curr.y);
                    component.max_x = @max(component.max_x, curr.x);
                    component.max_y = @max(component.max_y, curr.y);

                    for (Directions) |dir| {
                        const neighbor_tile = self.getNeighbouringTile(curr.x, curr.y, dir.direction) orelse continue;
                        if (neighbor_tile.data == .empty) continue;

                        const nx = @as(usize, @intCast(@as(isize, @intCast(curr.x)) + dir.offset.dx));
                        const ny = @as(usize, @intCast(@as(isize, @intCast(curr.y)) + dir.offset.dy));

                        if (visited[ny * self.width + nx]) continue;

                        visited[ny * self.width + nx] = true;
                        try queue.append(.{ .x = nx, .y = ny });
                    }
                }

                try components.append(component);
            }
        }

        if (components.items.len <= 1) {
            return null;
        }

        // sort by size
        const sort_ctx = struct {
            pub fn lessThan(_: @This(), lhs: Component, rhs: Component) bool {
                return lhs.tiles.items.len > rhs.tiles.items.len;
            }
        };
        std.mem.sort(Component, components.items, sort_ctx{}, sort_ctx.lessThan);

        var new_objects = std.ArrayList(TileObject).init(allocator);

        // keep the largest component, move others
        for (components.items[1..]) |*comp| {
            const w = comp.max_x - comp.min_x + 1;
            const h = comp.max_y - comp.min_y + 1;

            const id = id_gen_fn(id_gen_ctx);
            var new_obj = try TileObject.init(allocator, id, w, h, self.position, self.rotation);

            if (comp.tiles.items.len == 1) {
                new_obj.object_type = .debris;
            } else {
                new_obj.object_type = self.object_type;
            }

            // calculate new position
            const min_x_f = @as(f32, @floatFromInt(comp.min_x));
            const min_y_f = @as(f32, @floatFromInt(comp.min_y));
            const w_new_f = @as(f32, @floatFromInt(w));
            const h_new_f = @as(f32, @floatFromInt(h));
            const w_old_f = @as(f32, @floatFromInt(self.width));
            const h_old_f = @as(f32, @floatFromInt(self.height));

            const offset_local_x = 8.0 * min_x_f + 4.0 * (w_new_f - w_old_f);
            const offset_local_y = 8.0 * min_y_f + 4.0 * (h_new_f - h_old_f);

            const cos_rot = @cos(self.rotation);
            const sin_rot = @sin(self.rotation);

            const offset_world_x = offset_local_x * cos_rot - offset_local_y * sin_rot;
            const offset_world_y = offset_local_x * sin_rot + offset_local_y * cos_rot;

            new_obj.position.x += offset_world_x;
            new_obj.position.y += offset_world_y;

            // transfer tiles
            for (comp.tiles.items) |coords| {
                const src_tile = self.getTile(coords.x, coords.y).?.*;
                const dst_x = coords.x - comp.min_x;
                const dst_y = coords.y - comp.min_y;

                new_obj.setTile(dst_x, dst_y, src_tile);

                // transfer inventory
                const old_idx = coords.y * self.width + coords.x;
                if (self.inventories.fetchRemove(old_idx)) |kv| {
                    const new_idx = dst_y * w + dst_x;
                    try new_obj.inventories.put(new_idx, kv.value);
                }

                self.setEmptyTile(coords.x, coords.y);
            }

            new_obj.dirty = true;
            try new_objects.append(new_obj);
        }

        self.dirty = true;
        return new_objects;
    }

    pub fn recalculatePhysics(self: *Self, physics: *Physics) !void {
        var linear_velocity = Vec2.init(0, 0);
        var angular_velocity: f32 = 0.0;

        if (self.body_id.isValid()) {
            self.position = physics.getPosition(self.body_id);
            self.rotation = physics.getRotation(self.body_id);

            linear_velocity = physics.getLinearVelocity(self.body_id);
            angular_velocity = physics.getAngularVelocity(self.body_id);

            physics.destroyBody(self.body_id);
            self.body_id = BodyId.invalid;
        }

        var physics_tiles = std.ArrayList(PhysicsTileData).init(self.allocator);
        defer physics_tiles.deinit();

        const visited = try self.allocator.alloc(bool, self.width * self.height);
        defer self.allocator.free(visited);
        @memset(visited, false);

        for (0..self.height) |y| {
            for (0..self.width) |x| {
                if (visited[y * self.width + x]) {
                    continue;
                }

                const tile = self.getTile(x, y) orelse continue;
                const density: f32 = switch (tile.data) {
                    .ship_part => |ship_data| PartStats.getDensity(ship_data.kind),
                    .terrain => 1.0,
                    .empty => 0.0,
                };

                if (density == 0.0) {
                    continue;
                }

                // greedy meshing
                var w: usize = 1;
                var h: usize = 1;

                // expand horizontal
                while (x + w < self.width) : (w += 1) {
                    if (visited[y * self.width + (x + w)]) break;

                    const next_tile = self.getTile(x + w, y) orelse break;
                    const next_density: f32 = switch (next_tile.data) {
                        .ship_part => |ship_data| PartStats.getDensity(ship_data.kind),
                        .terrain => 1.0,
                        .empty => 0.0,
                    };

                    if (next_density != density) break;
                }

                // expand vertical
                can_expand_h: while (y + h < self.height) : (h += 1) {
                    for (0..w) |dx| {
                        if (visited[(y + h) * self.width + (x + dx)]) break :can_expand_h;

                        const next_tile = self.getTile(x + dx, y + h) orelse break :can_expand_h;
                        const next_density: f32 = switch (next_tile.data) {
                            .ship_part => |ship_data| PartStats.getDensity(ship_data.kind),
                            .terrain => 1.0,
                            .empty => 0.0,
                        };

                        if (next_density != density) break :can_expand_h;
                    }
                }

                // mark visited
                for (0..h) |dy| {
                    for (0..w) |dx| {
                        visited[(y + dy) * self.width + (x + dx)] = true;
                    }
                }

                const object_center_x = @as(f32, @floatFromInt(self.width)) * 4.0;
                const object_center_y = @as(f32, @floatFromInt(self.height)) * 4.0;

                const start_x = @as(f32, @floatFromInt(x)) * 8.0;
                const start_y = @as(f32, @floatFromInt(y)) * 8.0;

                const width_px = @as(f32, @floatFromInt(w)) * 8.0;
                const height_px = @as(f32, @floatFromInt(h)) * 8.0;

                const final_center_x = (start_x - object_center_x) + (width_px * 0.5);
                const final_center_y = (start_y - object_center_y) + (height_px * 0.5);

                try physics_tiles.append(PhysicsTileData{
                    .pos = Vec2.init(final_center_x, final_center_y),
                    .half_width = width_px * 0.5,
                    .half_height = height_px * 0.5,
                    .density = density,
                    .layer = if (self.object_type == .debris) .debris else .default,
                });
            }
        }

        if (physics_tiles.items.len == 0) {
            return;
        }

        self.body_id = try physics.createBody(self.position, self.rotation);

        try physics.createTileShape(self.body_id, physics_tiles.items);

        physics.setLinearVelocity(self.body_id, linear_velocity);
        physics.setAngularVelocity(self.body_id, angular_velocity);

        try self.rebuildThrusters();
    }

    fn rebuildThrusters(self: *Self) !void {
        self.thrusters.clearRetainingCapacity();

        if (self.object_type != .ship_part and self.object_type != .enemy_drone) {
            return;
        }

        for (0..self.width) |x| {
            for (0..self.height) |y| {
                const tile = self.getTile(x, y) orelse continue;
                const ship_part = tile.getShipPart() orelse continue;

                if (ship_part.kind == .chemical_thruster) {
                    var power = PartStats.getEnginePower(ship_part.tier);
                    if (PartStats.isBroken(ship_part)) {
                        power *= 0.1;
                    }

                    const object_center_x = @as(f32, @floatFromInt(self.width)) * 4.0;
                    const object_center_y = @as(f32, @floatFromInt(self.height)) * 4.0;
                    const local_x = @as(f32, @floatFromInt(x)) * 8.0 + 4.0 - object_center_x;
                    const local_y = @as(f32, @floatFromInt(y)) * 8.0 + 4.0 - object_center_y;

                    try self.thrusters.append(.{
                        .kind = .main,
                        .x = local_x,
                        .y = local_y,
                        .direction = ship_part.rotation orelse .north,
                        .power = power,
                    });
                } else if (ship_part.kind == .smart_core and PartModule.has(ship_part.modules, PartModule.thruster)) {
                    var power = PartStats.getEnginePower(ship_part.tier);
                    if (PartStats.isBroken(ship_part)) {
                        power *= 0.1;
                    }

                    power *= 0.02;

                    const object_center_x = @as(f32, @floatFromInt(self.width)) * 4.0;
                    const object_center_y = @as(f32, @floatFromInt(self.height)) * 4.0;
                    const local_x = @as(f32, @floatFromInt(x)) * 8.0 + 4.0 - object_center_x;
                    const local_y = @as(f32, @floatFromInt(y)) * 8.0 + 4.0 - object_center_y;

                    // smart_core thrusters are omnidirectional
                    const directions = [_]Direction{ .north, .east, .south, .west };
                    for (directions) |dir| {
                        try self.thrusters.append(.{
                            .kind = .main,
                            .x = local_x,
                            .y = local_y,
                            .direction = dir,
                            .power = power,
                        });
                    }
                }
            }
        }
    }
};
