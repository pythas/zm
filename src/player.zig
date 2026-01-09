const std = @import("std");

const Vec2 = @import("vec2.zig").Vec2;
const Tile = @import("tile.zig").Tile;
const Direction = @import("tile.zig").Direction;
const Offset = @import("tile.zig").Offset;
const TileReference = @import("tile.zig").TileReference;
const TileCoords = @import("tile.zig").TileCoords;
const TileObject = @import("tile_object.zig").TileObject;
const InputManager = @import("input/input_manager.zig").InputManager;
const GameAction = @import("input/input_manager.zig").GameAction;
const Physics = @import("box2d_physics.zig").Physics;
const PhysicsLogic = @import("systems/physics_logic.zig").PhysicsLogic;
const InventoryLogic = @import("systems/inventory_logic.zig").InventoryLogic;
const World = @import("world.zig").World;
const PartKind = @import("tile.zig").PartKind;
const PartStats = @import("ship.zig").PartStats;
const rng = @import("rng.zig");
const config = @import("config.zig");

pub const Action = enum {
    laser,
    mining,
    railgun,
};

pub const PlayerController = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    target_id: u64,
    locked_target_id: ?u64 = null,

    current_action: Action,
    railgun_cooldown: f32 = 0.0,
    laser_cooldown: f32 = 0.0,
    flight_assist_enabled: bool = true,

    tile_actions: std.ArrayList(TileAction),

    pub fn init(allocator: std.mem.Allocator, target_id: u64) Self {
        return .{
            .allocator = allocator,
            .target_id = target_id,
            .current_action = .laser,
            .railgun_cooldown = 0.0,
            .laser_cooldown = 0.0,
            .flight_assist_enabled = true,
            .tile_actions = std.ArrayList(TileAction).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.tile_actions.deinit();
    }

    pub fn update(
        self: *Self,
        dt: f32,
        world: *World,
        input: *const InputManager,
    ) !void {
        if (self.railgun_cooldown > 0.0) self.railgun_cooldown -= dt;
        if (self.laser_cooldown > 0.0) self.laser_cooldown -= dt;

        const ship = world.getObjectById(self.target_id) orelse return;

        self.updateMovementInputs(ship, world, input);
        try self.updateCombatInputs(ship, world, input);
        try self.updateMouseInputs(ship, world, input);
        try self.updateDebrisPickup(ship, world);
        try self.updateTileActions(dt, world);
    }

    fn updateMovementInputs(self: *Self, ship: *TileObject, world: *World, input: *const InputManager) void {
        if (input.isActionPressed(.toggle_flight_assist)) {
            self.flight_assist_enabled = !self.flight_assist_enabled;
            const text = if (self.flight_assist_enabled) "Flight Assist: ON" else "Flight Assist: OFF";
            world.notifications.add(text, .{ .r = 0.5, .g = 0.8, .b = 1.0, .a = 1.0 }, .auto_dismiss);
        }

        var has_linear_input = false;

        if (input.isActionDown(.move_forward)) {
            PhysicsLogic.applyInputThrust(ship, &world.physics, .forward);
            has_linear_input = true;
        }
        if (input.isActionDown(.move_backward)) {
            PhysicsLogic.applyInputThrust(ship, &world.physics, .backward);
            has_linear_input = true;
        }
        if (input.isActionDown(.move_left)) {
            PhysicsLogic.applyInputThrust(ship, &world.physics, .left);
            has_linear_input = true;
        }
        if (input.isActionDown(.move_right)) {
            PhysicsLogic.applyInputThrust(ship, &world.physics, .right);
            has_linear_input = true;
        }

        if (self.flight_assist_enabled) {
            PhysicsLogic.stabilize(ship, &world.physics, !has_linear_input);
        }
    }

    fn updateCombatInputs(self: *Self, ship: *TileObject, world: *World, input: *const InputManager) !void {
        if (input.isActionPressed(.cycle_target)) {
            self.cycleTarget(world);
        }

        if (input.isActionDown(.fire_secondary)) {
            if (self.locked_target_id != null) {
                try self.fireLasersAtLockedTarget(ship, world);
            }
        }
    }

    fn updateMouseInputs(self: *Self, ship: *TileObject, world: *World, input: *const InputManager) !void {
        if (!input.isActionDown(.fire_primary)) return;

        const world_pos = input.getMouseWorldPos(world.camera);
        const auto_target = input.isActionDown(.mining_auto_target);

        switch (self.current_action) {
            .mining => {
                for (world.objects.items) |*object| {
                    if (object.id == self.target_id) continue;

                    var target_x: i32 = 0;
                    var target_y: i32 = 0;

                    if (auto_target) {
                        if (object.getTileCoordsAtWorldPos(world_pos)) |_| {
                            if (object.object_type == .debris) continue;

                            var best_dist: f32 = std.math.floatMax(f32);
                            var found = false;

                            for (0..object.height) |y| {
                                for (0..object.width) |x| {
                                    if (object.getTile(x, y)) |t| {
                                        if (t.data != .empty) {
                                            const pos = object.getTileWorldPos(x, y);
                                            const dist = pos.sub(ship.position).lengthSq();
                                            if (dist < best_dist) {
                                                best_dist = dist;
                                                target_x = @intCast(x);
                                                target_y = @intCast(y);
                                                found = true;
                                            }
                                        }
                                    }
                                }
                            }
                            if (!found) continue;
                        } else {
                            continue;
                        }
                    } else {
                        const coords = object.getTileCoordsAtWorldPos(world_pos) orelse continue;
                        const tile = object.getTile(coords.x, coords.y) orelse continue;
                        if (tile.data == .empty) continue;
                        target_x = @intCast(coords.x);
                        target_y = @intCast(coords.y);
                    }

                    const target_pos = object.getTileWorldPos(@intCast(target_x), @intCast(target_y));
                    const best_candidate = try self.getMiningCandidate(ship, target_pos);

                    if (best_candidate == null) {
                        if (auto_target) break;
                        continue;
                    }

                    const radius: i32 = @intCast(PartStats.getMiningRadius(best_candidate.?.tier));
                    const center_x: i32 = target_x;
                    const center_y: i32 = target_y;

                    var dy: i32 = -radius;
                    while (dy <= radius) : (dy += 1) {
                        var dx: i32 = -radius;
                        while (dx <= radius) : (dx += 1) {
                            if (@abs(dx) + @abs(dy) <= radius) {
                                const tx_i = center_x + dx;
                                const ty_i = center_y + dy;
                                if (tx_i < 0 or ty_i < 0) continue;

                                const tx: usize = @intCast(tx_i);
                                const ty: usize = @intCast(ty_i);

                                if (object.getTile(tx, ty)) |target_tile| {
                                    if (target_tile.data == .empty) continue;
                                    try self.startMining(best_candidate.?.coords, .{
                                        .object_id = object.id,
                                        .tile_x = tx,
                                        .tile_y = ty,
                                    }, PartStats.getMiningDuration(best_candidate.?.tier));
                                }
                            }
                        }
                    }
                    break;
                }
            },
            .laser => {
                try self.fireLasersAtPosition(ship, world, world_pos);
            },
            .railgun => {
                try self.fireRailgun(ship, world, world_pos);
            },
        }
    }

    fn updateDebrisPickup(self: *Self, ship: *TileObject, world: *World) !void {
        _ = self;
        const pickup_radius = 32.0; // 4 tiles
        const pickup_radius_sq = pickup_radius * pickup_radius;

        var i: usize = 0;
        while (i < world.objects.items.len) {
            var debris = &world.objects.items[i];
            if (debris.object_type != .debris) {
                i += 1;
                continue;
            }

            const dist = debris.position.sub(ship.position).lengthSq();
            if (dist < pickup_radius_sq) {
                var tile = &debris.tiles[0];
                var resources = tile.data.terrain.resources;
                var new_resources = try std.BoundedArray(@import("tile.zig").ResourceAmount, 4).init(0);
                var picked_up_something = false;
                var fully_depleted = true;

                for (resources.slice()) |res_amount| {
                    const amount = res_amount.amount;
                    if (amount == 0) continue;

                    const remaining = try InventoryLogic.addItemToInventory(ship, .{ .resource = res_amount.resource }, amount, debris.position);
                    const added = amount - remaining;

                    if (added > 0) {
                        picked_up_something = true;
                        if (world.research_manager.reportResourcePickup(res_amount.resource, added)) {
                            world.notifications.add("Unlocked: Welding", .{ .r = 1.0, .g = 0.8, .b = 0.0, .a = 1.0 }, .manual_dismiss);
                        }
                        var buf: [64]u8 = undefined;
                        const text = std.fmt.bufPrint(&buf, "+ {d} {s}", .{ added, @tagName(res_amount.resource) }) catch "+ resource";
                        world.notifications.add(text, .{ .r = 0.8, .g = 1.0, .b = 0.8, .a = 1.0 }, .auto_dismiss);
                    }

                    if (remaining > 0) {
                        fully_depleted = false;
                        try new_resources.append(.{ .resource = res_amount.resource, .amount = @intCast(remaining) });
                    }
                }

                if (fully_depleted) {
                    world.physics.destroyBody(debris.body_id);
                    debris.deinit();
                    _ = world.objects.swapRemove(i);
                } else {
                    tile.data.terrain.resources = new_resources;
                    debris.dirty = true;
                    i += 1;
                }
            } else {
                i += 1;
            }
        }
    }

    fn updateTileActions(self: *Self, dt: f32, world: *World) !void {
        var i: usize = self.tile_actions.items.len;
        while (i > 0) {
            i -= 1;
            var action = &self.tile_actions.items[i];
            action.progress += dt;

            if (!action.isActive()) {
                if (world.getObjectById(action.target.object_id)) |target_obj| {
                    const tx = action.target.tile_x;
                    const ty = action.target.tile_y;

                    if (target_obj.getTile(tx, ty)) |tile| {
                        if (tile.data != .empty) {
                            const debris_pos = target_obj.getTileWorldPos(tx, ty);
                            const new_id = world.generateObjectId();
                            var debris = try TileObject.init(self.allocator, new_id, 1, 1, debris_pos, target_obj.rotation);
                            debris.object_type = .debris;
                            debris.setTile(0, 0, tile.*);
                            try PhysicsLogic.recalculatePhysics(&debris, &world.physics);

                            if (target_obj.body_id.isValid()) {
                                const parent_vel = world.physics.getLinearVelocity(target_obj.body_id);
                                const parent_ang_vel = world.physics.getAngularVelocity(target_obj.body_id);
                                const r = debris.position.sub(target_obj.position);
                                const tan_vel = Vec2.init(-parent_ang_vel * r.y, parent_ang_vel * r.x);
                                var final_vel = parent_vel.add(tan_vel);

                                const rand = rng.random();
                                final_vel.x += (rand.float(f32) - 0.5) * 10.0;
                                final_vel.y += (rand.float(f32) - 0.5) * 10.0;

                                world.physics.setLinearVelocity(debris.body_id, final_vel);
                                world.physics.setAngularVelocity(debris.body_id, parent_ang_vel + (rand.float(f32) - 0.5) * 2.0);
                            }
                            try world.objects.append(debris);
                        }
                    }
                    if (world.getObjectById(action.target.object_id)) |obj| obj.setEmptyTile(tx, ty);
                }
                _ = self.tile_actions.orderedRemove(i);
            }
        }
    }

    pub const MiningCandidate = struct { coords: TileCoords, dist: f32, tier: u8 };

    pub fn getMiningCandidate(self: *const Self, ship: *TileObject, target_pos: Vec2) !?MiningCandidate {
        const tile_refs = try ship.getTilesByPartKind(.mining_laser);
        defer self.allocator.free(tile_refs);

        var best: ?MiningCandidate = null;

        for (tile_refs) |ref| {
            var busy = false;
            for (self.tile_actions.items) |act| {
                if (act.source.x == ref.tile_x and act.source.y == ref.tile_y) {
                    busy = true;
                    break;
                }
            }
            if (busy) continue;

            const tile = ship.getTile(ref.tile_x, ref.tile_y).?;
            const part = tile.getShipPart().?;
            const is_broken = PartStats.isBroken(part);

            const range = PartStats.getMiningRangeSq(part.tier, is_broken);
            const dist = ship.getDistanceToTileSq(ref.tile_x, ref.tile_y, target_pos);

            if (dist <= range) {
                if (best == null or dist < best.?.dist) {
                    best = .{
                        .coords = .{ .x = ref.tile_x, .y = ref.tile_y },
                        .dist = dist,
                        .tier = part.tier,
                    };
                }
            }
        }

        return best;
    }

    fn fireRailgun(self: *Self, ship: *TileObject, world: *World, world_pos: Vec2) !void {
        if (self.railgun_cooldown > 0.0) return;
        const tile_refs = try ship.getTilesByPartKind(.railgun);
        defer self.allocator.free(tile_refs);

        var best_pos: ?Vec2 = null;
        var best_tier: u8 = 1;
        var min_d_sq: f32 = std.math.floatMax(f32);

        for (tile_refs) |ref| {
            const p_pos = ship.getTileWorldPos(ref.tile_x, ref.tile_y);
            const d_sq = p_pos.sub(world_pos).lengthSq();
            const part = ship.getTile(ref.tile_x, ref.tile_y).?.getShipPart().?;
            if (PartStats.isBroken(part)) continue;

            if (d_sq < min_d_sq) {
                min_d_sq = d_sq;
                best_pos = p_pos;
                best_tier = part.tier;
            }
        }

        if (best_pos) |pos| {
            const dir = world_pos.sub(pos).normalize();
            var curr = pos;
            var power = PartStats.getRailgunPower(best_tier);
            const max_d = PartStats.getRailgunRange(best_tier);
            var traveled: f32 = 0.0;

            while (traveled < max_d and power > 0) {
                curr = curr.add(dir.mulScalar(4.0));
                traveled += 4.0;

                for (world.objects.items) |*obj| {
                    if (obj.id == self.target_id or obj.object_type == .debris) continue;
                    if (obj.getTileCoordsAtWorldPos(curr)) |c| {
                        if (obj.getTile(c.x, c.y)) |t| {
                            if (t.data != .empty) {
                                const h = t.getHealth() orelse 10.0;
                                const consume = @min(power, h);

                                if (power >= h) obj.setEmptyTile(c.x, c.y) else switch (t.data) {
                                    .ship_part => |*p| p.health -= power,
                                    .terrain => |*tr| tr.health -= power,
                                    else => {},
                                }
                                power -= consume;

                                obj.dirty = true;

                                if (obj.body_id.isValid()) {
                                    world.physics.addLinearImpulseAtPoint(
                                        obj.body_id,
                                        dir.mulScalar(consume * PartStats.getRailgunImpulseMultiplier()),
                                        curr,
                                        true,
                                    );
                                }
                            }
                        }
                    }
                }
            }
            try world.railgun_trails.append(.{ .start = pos, .end = curr, .lifetime = 0.5, .max_lifetime = 0.5 });
            self.railgun_cooldown = PartStats.getRailgunCooldown(best_tier);
        }
    }

    fn cycleTarget(self: *Self, world: *World) void {
        const ship = world.getObjectById(self.target_id) orelse return;

        const Candidate = struct { id: u64, dist: f32 };

        var candidates = std.ArrayList(Candidate).init(self.allocator);
        defer candidates.deinit();

        const max_targeting_range = config.combat.max_targeting_range;
        const max_range_sq = max_targeting_range * max_targeting_range;

        for (world.objects.items) |*obj| {
            if (obj.id == self.target_id or obj.object_type == .debris or obj.object_type == .debris or !obj.body_id.isValid()) continue;

            const dist = obj.position.sub(ship.position).lengthSq();
            if (dist <= max_range_sq) {
                candidates.append(.{ .id = obj.id, .dist = dist }) catch continue;
            }
        }

        if (candidates.items.len == 0) {
            self.locked_target_id = null;
            world.notifications.add("No Target Found", .{ .r = 1.0, .g = 1.0, .b = 0.0, .a = 1.0 }, .auto_dismiss);
            return;
        }

        const SortContext = struct {};
        std.mem.sort(Candidate, candidates.items, SortContext{}, struct {
            fn lessThan(_: SortContext, lhs: Candidate, rhs: Candidate) bool {
                return lhs.dist < rhs.dist;
            }
        }.lessThan);

        if (self.locked_target_id) |curr_id| {
            var found = false;
            for (candidates.items, 0..) |cand, i| {
                if (cand.id == curr_id) {
                    self.locked_target_id = candidates.items[(i + 1) % candidates.items.len].id;
                    found = true;
                    break;
                }
            }

            if (!found) {
                self.locked_target_id = candidates.items[0].id;
            }
        } else {
            self.locked_target_id = candidates.items[0].id;
        }

        var buf: [64]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "Target Locked: {d}", .{self.locked_target_id.?}) catch "Target Locked";
        world.notifications.add(text, .{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 }, .auto_dismiss);
    }

    fn fireLasersAtPosition(self: *Self, ship: *TileObject, world: *World, target_pos: Vec2) !void {
        if (self.laser_cooldown > 0.0) return;

        const lasers = try ship.getTilesByPartKind(.laser);
        defer self.allocator.free(lasers);

        if (lasers.len == 0) return;

        var fired = false;
        for (lasers) |ref| {
            const part = ship.getTile(ref.tile_x, ref.tile_y).?.getShipPart().?;
            const is_broken = PartStats.isBroken(part);
            const range_sq = PartStats.getLaserRangeSq(part.tier, is_broken);
            const start = ship.getTileWorldPos(ref.tile_x, ref.tile_y);

            if (start.sub(target_pos).lengthSq() <= range_sq) {
                const damage = PartStats.getLaserDamage(part.tier);
                const hit_pos = self.performGlobalLaserRaycast(world, ship.id, start, target_pos, damage);
                try world.laser_beams.append(.{ .start = start, .end = hit_pos, .lifetime = 0.2, .max_lifetime = 0.2, .color = .{ 1.0, 0.2, 0.2, 1.0 } });
                fired = true;
            }
        }

        if (fired) {
            self.laser_cooldown = config.combat.laser_cooldown;
        }
    }

    fn performGlobalLaserRaycast(self: *Self, world: *World, ignore_id: u64, start: Vec2, end: Vec2, damage: f32) Vec2 {
        var hit = end;
        const diff = end.sub(start);
        const dist = diff.length();
        const dir = diff.normalize();
        var d: f32 = 0.0;

        while (d < dist) : (d += config.combat.laser_raycast_step) {
            const pt = start.add(dir.mulScalar(d));

            for (world.objects.items) |*obj| {
                if (obj.id == ignore_id or obj.object_type == .debris) continue;

                if (obj.getTileCoordsAtWorldPos(pt)) |coords| {
                    if (obj.getTile(coords.x, coords.y)) |tile| {
                        if (tile.data != .empty) {
                            hit = obj.getTileWorldPos(coords.x, coords.y);
                            self.applyDamage(obj, tile, coords.x, coords.y, damage);
                            return hit;
                        }
                    }
                }
            }
        }
        return hit;
    }

    fn fireLasersAtLockedTarget(self: *Self, ship: *TileObject, world: *World) !void {
        if (self.laser_cooldown > 0.0) return;

        const target_id = self.locked_target_id orelse return;
        const target_obj = world.getObjectById(target_id) orelse {
            self.locked_target_id = null;
            return;
        };

        const lasers = try ship.getTilesByPartKind(.laser);
        defer self.allocator.free(lasers);

        if (lasers.len == 0) return;

        var target_pos = target_obj.position;

        for (0..5) |_| {
            const tx = rng.random().uintAtMost(usize, target_obj.width - 1);
            const ty = rng.random().uintAtMost(usize, target_obj.height - 1);

            if (target_obj.getTile(tx, ty)) |tile| {
                if (tile.data != .empty) {
                    target_pos = target_obj.getTileWorldPos(tx, ty);
                    break;
                }
            }
        }

        var fired = false;
        for (lasers) |ref| {
            var busy = false;
            for (self.tile_actions.items) |act| {
                if (act.source.x == ref.tile_x and act.source.y == ref.tile_y) {
                    busy = true;
                    break;
                }
            }
            if (busy) continue;

            const part = ship.getTile(ref.tile_x, ref.tile_y).?.getShipPart().?;
            const is_broken = PartStats.isBroken(part);
            const range = PartStats.getLaserRangeSq(part.tier, is_broken);

            if (ship.getDistanceToTileSq(ref.tile_x, ref.tile_y, target_pos) <= range) {
                const start = ship.getTileWorldPos(ref.tile_x, ref.tile_y);
                const hit_pos = self.performLaserRaycast(target_obj, start, target_pos, PartStats.getLaserDamage(part.tier));

                try world.laser_beams.append(.{ .start = start, .end = hit_pos, .lifetime = 0.2, .max_lifetime = 0.2, .color = .{ 0.2, 1.0, 0.2, 1.0 } });

                fired = true;
            }
        }

        if (fired) {
            self.laser_cooldown = config.combat.laser_cooldown;
        }
    }

    fn performLaserRaycast(self: *Self, ship: *TileObject, start: Vec2, end: Vec2, damage: f32) Vec2 {
        var hit = end;
        const diff = end.sub(start);
        const dist = diff.length();
        const dir = diff.normalize();
        var d: f32 = 0.0;

        while (d < dist) : (d += config.combat.laser_raycast_step) {
            const pt = start.add(dir.mulScalar(d));

            if (ship.getTileCoordsAtWorldPos(pt)) |coords| {
                if (ship.getTile(coords.x, coords.y)) |tile| {
                    if (tile.data != .empty) {
                        hit = ship.getTileWorldPos(coords.x, coords.y);
                        self.applyDamage(ship, tile, coords.x, coords.y, damage);
                        break;
                    }
                }
            }
        }

        return hit;
    }

    fn applyDamage(_: *Self, ship: *TileObject, tile: *Tile, x: usize, y: usize, damage: f32) void {
        const health = tile.getHealth() orelse 0.0;
        if (health <= damage) {
            ship.setEmptyTile(x, y);
            ship.dirty = true;
        } else switch (tile.data) {
            .ship_part => |*p| p.health -= damage,
            .terrain => |*t| t.health -= damage,
            else => {},
        }
    }

    pub fn startMining(self: *Self, source: TileCoords, target: TileReference, duration: f32) !void {
        try self.tile_actions.append(TileAction.init(.mine, source, target, duration));
    }

    // pub fn performSensorSweep(self: *Self, world: *World, origin: Vec2, range: f32) !void {
    //     var hits = std.ArrayList(Vec2).init(self.allocator);
    //     defer hits.deinit();
    //
    //     const segments = 128;
    //     for (0..segments) |i| {
    //         const angle = (@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(segments))) * std.math.tau;
    //         const target = origin.add(Vec2.init(@cos(angle) * range, @sin(angle) * range));
    //
    //         // We pass null for ignore_body here because the sweep should probably see everything,
    //         // or we could pass the player's body ID if we had easy access to it here.
    //         // For now, null is safe as it just means we might hit ourselves if origin is inside.
    //         const hit = world.physics.castRay(origin, target, null);
    //
    //         if (hit.hit) {
    //             try hits.append(hit.point);
    //         }
    //     }
    //     // In the future, this list would be sent to the renderer or UI to draw the "ping" effect.
    // }
};

pub const TileAction = struct {
    const Self = @This();
    pub const Kind = enum { mine };

    kind: Kind,
    source: TileCoords,
    target: TileReference,
    progress: f32,
    duration: f32,

    pub fn init(
        kind: Kind,
        source: TileCoords,
        target: TileReference,
        duration: f32,
    ) Self {
        return .{
            .kind = kind,
            .source = source,
            .target = target,
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
