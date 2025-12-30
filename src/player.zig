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
const UiVec4 = @import("renderer/ui_renderer.zig").UiVec4;
const RailgunTrail = @import("effects.zig").RailgunTrail;

pub const Action = enum {
    laser,
    railgun,
};

pub const PlayerController = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    target_id: u64,
    current_action: Action,
    railgun_cooldown: f32 = 0.0,

    tile_actions: std.ArrayList(TileAction),

    pub fn init(allocator: std.mem.Allocator, target_id: u64) Self {
        return .{
            .allocator = allocator,
            .target_id = target_id,
            .current_action = .laser,
            .railgun_cooldown = 0.0,
            .tile_actions = std.ArrayList(TileAction).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.tile_actions.deinit();
    }

    pub const LaserCandidate = struct {
        coords: TileCoords,
        dist: f32,
        tier: u8,
    };

    pub fn getLaserCandidate(
        self: *const Self,
        ship: *TileObject,
        target_pos: Vec2,
    ) !?LaserCandidate {
        const tile_refs = try ship.getTilesByPartKind(.laser);
        defer self.allocator.free(tile_refs);

        var laser_candidates = std.ArrayList(LaserCandidate).init(self.allocator);
        defer laser_candidates.deinit();

        for (tile_refs) |tile_ref| {
            var is_used = false;
            for (self.tile_actions.items) |tile_action| {
                if (tile_action.source.x == tile_ref.tile_x and
                    tile_action.source.y == tile_ref.tile_y)
                {
                    is_used = true;
                    break;
                }
            }

            if (!is_used) {
                // check if in range
                const ti = ship.getTile(tile_ref.tile_x, tile_ref.tile_y) orelse continue;
                const ship_part = ti.getShipPart() orelse continue;
                const is_broken = PartStats.isBroken(ship_part);

                const range = PartStats.getLaserRangeSq(ship_part.tier, is_broken);
                const dist = ship.getDistanceToTileSq(
                    tile_ref.tile_x,
                    tile_ref.tile_y,
                    target_pos,
                );

                if (dist > range) {
                    continue;
                }

                try laser_candidates.append(.{
                    .coords = .{
                        .x = tile_ref.tile_x,
                        .y = tile_ref.tile_y,
                    },
                    .dist = dist,
                    .tier = ship_part.tier,
                });
            }
        }

        if (laser_candidates.items.len == 0) {
            return null;
        }

        // get closest laser
        var min: ?LaserCandidate = null;
        for (laser_candidates.items) |candidate| {
            if (min == null or candidate.dist < min.?.dist) {
                min = candidate;
            }
        }

        return min;
    }

    fn fireRailgun(self: *Self, ship: *TileObject, world: *World, world_pos: Vec2) !void {
        if (self.railgun_cooldown > 0.0) return;

        const tile_refs = try ship.getTilesByPartKind(.railgun);
        defer self.allocator.free(tile_refs);

        // find closest railgun
        var best_railgun_pos: ?Vec2 = null;
        var best_railgun_tier: u8 = 1;
        var min_dist_sq: f32 = std.math.floatMax(f32);

        for (tile_refs) |tile_ref| {
            const part_pos = ship.getTileWorldPos(tile_ref.tile_x, tile_ref.tile_y);
            const dist_sq = part_pos.sub(world_pos).lengthSq();

            // check if functional
            const tile = ship.getTile(tile_ref.tile_x, tile_ref.tile_y).?;
            const part = tile.getShipPart().?;
            if (PartStats.isBroken(part)) continue;

            if (dist_sq < min_dist_sq) {
                min_dist_sq = dist_sq;
                best_railgun_pos = part_pos;
                best_railgun_tier = part.tier;
            }
        }

        if (best_railgun_pos) |pos| {
            const dir = world_pos.sub(pos).normalize();
            var current_pos = pos;
            var remaining_power: f32 = PartStats.getRailgunPower(best_railgun_tier);
            const step_size: f32 = 4.0;
            const max_dist: f32 = PartStats.getRailgunRange(best_railgun_tier);
            var dist_traveled: f32 = 0.0;

            while (dist_traveled < max_dist and remaining_power > 0) {
                current_pos = current_pos.add(dir.mulScalar(step_size));
                dist_traveled += step_size;

                for (world.objects.items) |*obj| {
                    if (obj.id == self.target_id or obj.object_type == .debris) continue;

                    if (obj.getTileCoordsAtWorldPos(current_pos)) |coords| {
                        if (obj.getTile(coords.x, coords.y)) |tile| {
                            if (tile.data != .empty) {
                                const health = tile.getHealth() orelse 10.0;
                                var power_consumed: f32 = 0.0;

                                if (remaining_power >= health) {
                                    power_consumed = health;
                                    remaining_power -= health;
                                    obj.setEmptyTile(coords.x, coords.y);
                                } else {
                                    power_consumed = remaining_power;
                                    switch (tile.data) {
                                        .ship_part => |*p| p.health -= remaining_power,
                                        .terrain => |*t| t.health -= remaining_power,
                                        else => {},
                                    }
                                    remaining_power = 0;
                                    obj.dirty = true;
                                }

                                if (obj.body_id.isValid()) {
                                    const impulse_mag = power_consumed * PartStats.getRailgunImpulseMultiplier();
                                    const impulse = dir.mulScalar(impulse_mag);
                                    world.physics.addLinearImpulseAtPoint(obj.body_id, impulse, current_pos, true);
                                }
                            }
                        }
                    }
                }
            }

            try world.railgun_trails.append(.{
                .start = pos,
                .end = current_pos,
                .lifetime = 0.5,
                .max_lifetime = 0.5,
            });

            self.railgun_cooldown = PartStats.getRailgunCooldown(best_railgun_tier);
        }
    }

    pub fn update(
        self: *Self,
        dt: f32,
        world: *World,
        keyboard_state: *const KeyboardState,
        mouse_state: *const MouseState,
    ) !void {
        if (self.railgun_cooldown > 0.0) {
            self.railgun_cooldown -= dt;
        }

        var ship = world.getObjectById(self.target_id) orelse return;

        if (!keyboard_state.isDown(.left_shift)) {
            if (keyboard_state.isDown(.w)) {
                ship.applyInputThrust(&world.physics, .forward);
            }

            if (keyboard_state.isDown(.s)) {
                ship.applyInputThrust(&world.physics, .backward);
            }

            if (keyboard_state.isDown(.q)) {
                ship.applyInputThrust(&world.physics, .left);
            }

            if (keyboard_state.isDown(.e)) {
                ship.applyInputThrust(&world.physics, .right);
            }

            if (keyboard_state.isDown(.a)) {
                ship.applyInputTorque(&world.physics, .rotate_ccw);
            }

            if (keyboard_state.isDown(.d)) {
                ship.applyInputTorque(&world.physics, .rotate_cw);
            }
        } else {
            if (keyboard_state.isDown(.w)) {
                ship.applyInputThrust(&world.physics, .secondary_forward);
            }

            if (keyboard_state.isDown(.s)) {
                ship.applyInputThrust(&world.physics, .secondary_backward);
            }

            if (keyboard_state.isDown(.q)) {
                ship.applyInputThrust(&world.physics, .secondary_left);
            }

            if (keyboard_state.isDown(.e)) {
                ship.applyInputThrust(&world.physics, .secondary_right);
            }

            if (keyboard_state.isDown(.a)) {
                ship.applyInputTorque(&world.physics, .rotate_ccw);
            }

            if (keyboard_state.isDown(.d)) {
                ship.applyInputTorque(&world.physics, .rotate_cw);
            }
        }

        if (mouse_state.is_left_down) {
            const mouse_pos = mouse_state.getRelativePosition();
            const world_pos = world.camera.screenToWorld(mouse_pos);

            switch (self.current_action) {
                .laser => {
                    for (world.objects.items) |*object| {
                        if (object.id == self.target_id) {
                            continue;
                        }

                        const coords = object.getTileCoordsAtWorldPos(world_pos) orelse continue;
                        const tile = object.getTile(coords.x, coords.y) orelse continue;
                        if (tile.data == .empty) continue;

                        const target_pos = object.getTileWorldPos(coords.x, coords.y);

                        const best_candidate = try self.getLaserCandidate(ship, target_pos);

                        if (best_candidate == null) {
                            std.debug.print("No valid laser avaiable for mining\n", .{});
                            break;
                        }

                        var targets = std.ArrayList(TileReference).init(self.allocator);
                        defer targets.deinit();

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

                                    const tile_x: usize = @intCast(target_x);
                                    const tile_y: usize = @intCast(target_y);

                                    if (object.getTile(tile_x, tile_y)) |target_tile| {
                                        if (target_tile.data == .empty) continue;

                                        try targets.append(.{
                                            .object_id = object.id,
                                            .tile_x = tile_x,
                                            .tile_y = tile_y,
                                        });
                                    }
                                }
                            }
                        }

                        for (targets.items) |target| {
                            try self.startMining(best_candidate.?.coords, target);
                        }

                        break;
                    }
                },
                .railgun => {
                    try self.fireRailgun(ship, world, world_pos);
                },
            }
        }

        // pickup
        {
            const pickup_radius = 4 * 8;
            const pickup_radius_sq = pickup_radius * pickup_radius;

            var i: usize = 0;
            while (i < world.objects.items.len) {
                var debris = &world.objects.items[i];

                if (debris.object_type == .debris) {
                    const dist_sq = debris.position.sub(ship.position).lengthSq();

                    if (dist_sq < pickup_radius_sq) {
                        const tile = debris.tiles[0];
                        const resource_amount = tile.data.terrain.resources;

                        for (resource_amount.slice()) |res_amount| {
                            const amount = rng.random().intRangeAtMost(
                                u8,
                                0,
                                res_amount.amount,
                            );
                            const remaining = try ship.addItemToInventory(
                                .{ .resource = res_amount.resource },
                                amount,
                                debris.position,
                            );
                            const added = amount - remaining;

                            if (added > 0) {
                                _ = world.research_manager.reportResourcePickup(
                                    res_amount.resource,
                                    added,
                                );

                                var buf: [64]u8 = undefined;
                                const text = std.fmt.bufPrint(&buf, "+ {d} {s}", .{ added, @tagName(res_amount.resource) }) catch "+ resource";
                                world.notifications.add(text, .{ .r = 0.8, .g = 1.0, .b = 0.8, .a = 1.0 });
                            }
                        }

                        world.physics.destroyBody(debris.body_id);
                        debris.deinit();
                        _ = world.objects.swapRemove(i);

                        continue;
                    }
                }
                i += 1;
            }
        }

        // actions
        var i: usize = self.tile_actions.items.len;
        while (i > 0) {
            i -= 1;

            var tile_action = &self.tile_actions.items[i];
            tile_action.progress += dt;

            if (!tile_action.isActive()) {
                switch (tile_action.kind) {
                    .mine => {
                        std.debug.print("mine tile: {d} {d}\n", .{
                            tile_action.target.tile_x,
                            tile_action.target.tile_y,
                        });

                        if (world.getObjectById(tile_action.target.object_id)) |target_obj| {
                            const tx = tile_action.target.tile_x;
                            const ty = tile_action.target.tile_y;
                            const target_id = tile_action.target.object_id;

                            if (target_obj.getTile(tx, ty)) |tile| {
                                if (tile.data != .empty) {
                                    const debris_pos = target_obj.getTileWorldPos(tx, ty);

                                    const new_id = world.generateObjectId();
                                    var debris = try TileObject.init(
                                        self.allocator,
                                        new_id,
                                        1,
                                        1,
                                        debris_pos,
                                        target_obj.rotation,
                                    );
                                    debris.object_type = .debris;
                                    debris.setTile(0, 0, tile.*);

                                    try debris.recalculatePhysics(&world.physics);

                                    if (target_obj.body_id.isValid()) {
                                        const parent_vel = world.physics.getLinearVelocity(target_obj.body_id);
                                        const parent_ang_vel = world.physics.getAngularVelocity(target_obj.body_id);

                                        const r = debris.position.sub(target_obj.position);
                                        const tan_vel = Vec2.init(-parent_ang_vel * r.y, parent_ang_vel * r.x);
                                        var final_vel = parent_vel.add(tan_vel);

                                        // add random drift
                                        const rand = std.crypto.random;
                                        const drift_speed = 10.0;
                                        final_vel.x += (rand.float(f32) - 0.5) * drift_speed;
                                        final_vel.y += (rand.float(f32) - 0.5) * drift_speed;

                                        // add random rotation
                                        const rot_speed = 2.0;
                                        const final_ang_vel = parent_ang_vel + (rand.float(f32) - 0.5) * rot_speed;

                                        world.physics.setLinearVelocity(debris.body_id, final_vel);
                                        world.physics.setAngularVelocity(debris.body_id, final_ang_vel);
                                    }

                                    try world.objects.append(debris);
                                }
                            }

                            if (world.getObjectById(target_id)) |target_obj_refreshed| {
                                target_obj_refreshed.setEmptyTile(tx, ty);
                            }
                        }
                    },
                }

                _ = self.tile_actions.orderedRemove(i);
            }
        }
    }

    pub fn startMining(self: *Self, source: TileCoords, target: TileReference) !void {
        try self.tile_actions.append(
            TileAction.init(.mine, source, target, 3.0),
        );
    }
};

pub const TileAction = struct {
    const Self = @This();

    pub const Kind = enum {
        mine,
    };

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
