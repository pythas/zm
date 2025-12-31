const std = @import("std");

const Vec2 = @import("vec2.zig").Vec2;
const Tile = @import("tile.zig").Tile;
const Direction = @import("tile.zig").Direction;
const Offset = @import("tile.zig").Offset;
const TileReference = @import("tile.zig").TileReference;
const TileCoords = @import("tile.zig").TileCoords;
const TileObject = @import("tile_object.zig").TileObject;
const KeyboardState = @import("input.zig").KeyboardState;
const MouseState = @import("input.zig").MouseState;
const Physics = @import("box2d_physics.zig").Physics;
const World = @import("world.zig").World;
const PartKind = @import("tile.zig").PartKind;
const PartStats = @import("ship.zig").PartStats;
const rng = @import("rng.zig");

pub const Action = enum {
    laser,
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

    tile_actions: std.ArrayList(TileAction),

    pub fn init(allocator: std.mem.Allocator, target_id: u64) Self {
        return .{
            .allocator = allocator,
            .target_id = target_id,
            .current_action = .laser,
            .railgun_cooldown = 0.0,
            .laser_cooldown = 0.0,
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
        keyboard_state: *const KeyboardState,
        mouse_state: *const MouseState,
    ) !void {
        if (self.railgun_cooldown > 0.0) self.railgun_cooldown -= dt;
        if (self.laser_cooldown > 0.0) self.laser_cooldown -= dt;

        const ship = world.getObjectById(self.target_id) orelse return;

        self.updateMovementInputs(ship, world, keyboard_state);
        try self.updateCombatInputs(ship, world, keyboard_state);
        try self.updateMouseInputs(ship, world, mouse_state);
        try self.updateDebrisPickup(ship, world);
        try self.updateTileActions(dt, world);
    }

    fn updateMovementInputs(self: *Self, ship: *TileObject, world: *World, keyboard_state: *const KeyboardState) void {
        _ = self;
        const is_shifted = keyboard_state.isDown(.left_shift);

        if (!is_shifted) {
            if (keyboard_state.isDown(.w)) ship.applyInputThrust(&world.physics, .forward);
            if (keyboard_state.isDown(.s)) ship.applyInputThrust(&world.physics, .backward);
            if (keyboard_state.isDown(.q)) ship.applyInputThrust(&world.physics, .left);
            if (keyboard_state.isDown(.e)) ship.applyInputThrust(&world.physics, .right);
        } else {
            if (keyboard_state.isDown(.w)) ship.applyInputThrust(&world.physics, .secondary_forward);
            if (keyboard_state.isDown(.s)) ship.applyInputThrust(&world.physics, .secondary_backward);
            if (keyboard_state.isDown(.q)) ship.applyInputThrust(&world.physics, .secondary_left);
            if (keyboard_state.isDown(.e)) ship.applyInputThrust(&world.physics, .secondary_right);
        }

        if (keyboard_state.isDown(.a)) ship.applyInputTorque(&world.physics, .rotate_ccw);
        if (keyboard_state.isDown(.d)) ship.applyInputTorque(&world.physics, .rotate_cw);
    }

    fn updateCombatInputs(self: *Self, ship: *TileObject, world: *World, keyboard_state: *const KeyboardState) !void {
        if (keyboard_state.isPressed(.r)) {
            self.cycleTarget(world);
        }

        if (keyboard_state.isDown(.space)) {
            if (self.locked_target_id != null) {
                try self.fireLasersAtLockedTarget(ship, world);
            }
        }
    }

    fn updateMouseInputs(self: *Self, ship: *TileObject, world: *World, mouse_state: *const MouseState) !void {
        if (!mouse_state.is_left_down) return;

        const mouse_pos = mouse_state.getRelativePosition();
        const world_pos = world.camera.screenToWorld(mouse_pos);

        switch (self.current_action) {
            .laser => {
                for (world.objects.items) |*object| {
                    if (object.id == self.target_id) continue;

                    const coords = object.getTileCoordsAtWorldPos(world_pos) orelse continue;
                    const tile = object.getTile(coords.x, coords.y) orelse continue;
                    if (tile.data == .empty) continue;

                    const target_pos = object.getTileWorldPos(coords.x, coords.y);
                    const best_candidate = try self.getLaserCandidate(ship, target_pos);

                    if (best_candidate == null) break;

                    const radius: i32 = @intCast(PartStats.getLaserRadius(best_candidate.?.tier));
                    const center_x: i32 = @intCast(coords.x);
                    const center_y: i32 = @intCast(coords.y);

                    var dy: i32 = -radius;
                    while (dy <= radius) : (dy += 1) {
                        var dx: i32 = -radius;
                        while (dx <= radius) : (dx += 1) {
                            if (@abs(dx) + @abs(dy) <= radius) {
                                const target_x = center_x + dx;
                                const target_y = center_y + dy;
                                if (target_x < 0 or target_y < 0) continue;

                                const tx: usize = @intCast(target_x);
                                const ty: usize = @intCast(target_y);

                                if (object.getTile(tx, ty)) |target_tile| {
                                    if (target_tile.data == .empty) continue;
                                    try self.startMining(best_candidate.?.coords, .{
                                        .object_id = object.id,
                                        .tile_x = tx,
                                        .tile_y = ty,
                                    });
                                }
                            }
                        }
                    }
                    break;
                }
            },
            .railgun => {
                try self.fireRailgun(ship, world, world_pos);
            },
        }
    }

    fn updateDebrisPickup(self: *Self, ship: *TileObject, world: *World) !void {
        _ = self;
        const pickup_radius = 32.0; // 4 tiles * 8
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
                const tile = debris.tiles[0];
                const resources = tile.data.terrain.resources;

                for (resources.slice()) |res_amount| {
                    const amount = rng.random().intRangeAtMost(u8, 0, res_amount.amount);
                    const remaining = try ship.addItemToInventory(.{ .resource = res_amount.resource }, amount, debris.position);
                    const added = amount - remaining;

                    if (added > 0) {
                        _ = world.research_manager.reportResourcePickup(res_amount.resource, added);
                        var buf: [64]u8 = undefined;
                        const text = std.fmt.bufPrint(&buf, "+ {d} {s}", .{ added, @tagName(res_amount.resource) }) catch "+ resource";
                        world.notifications.add(text, .{ .r = 0.8, .g = 1.0, .b = 0.8, .a = 1.0 });
                    }
                }

                world.physics.destroyBody(debris.body_id);
                debris.deinit();
                _ = world.objects.swapRemove(i);
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
                            try debris.recalculatePhysics(&world.physics);

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

    pub const LaserCandidate = struct { coords: TileCoords, dist: f32, tier: u8 };

    pub fn getLaserCandidate(self: *const Self, ship: *TileObject, target_pos: Vec2) !?LaserCandidate {
        const tile_refs = try ship.getTilesByPartKind(.laser);
        defer self.allocator.free(tile_refs);

        var best: ?LaserCandidate = null;

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
            if (PartStats.isBroken(part)) continue;

            const range = PartStats.getLaserRangeSq(part.tier, false);
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

        const max_targeting_range = 500.0;
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
            world.notifications.add("No Target Found", .{ .r = 1.0, .g = 1.0, .b = 0.0, .a = 1.0 });
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
        world.notifications.add(text, .{ .r = 1.0, .g = 0.0, .b = 0.0, .a = 1.0 });
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
            self.laser_cooldown = 1.0;
        }
    }

    fn performLaserRaycast(self: *Self, ship: *TileObject, start: Vec2, end: Vec2, damage: f32) Vec2 {
        var hit = end;
        const diff = end.sub(start);
        const dist = diff.length();
        const dir = diff.normalize();
        var d: f32 = 0.0;

        while (d < dist) : (d += 4.0) {
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

    pub fn startMining(self: *Self, source: TileCoords, target: TileReference) !void {
        try self.tile_actions.append(TileAction.init(.mine, source, target, 3.0));
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
