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

pub const PlayerController = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    target_id: u64,

    tile_actions: std.ArrayList(TileAction),

    pub fn init(allocator: std.mem.Allocator, target_id: u64) Self {
        return .{
            .allocator = allocator,
            .target_id = target_id,
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
        var ship = world.getObjectById(self.target_id) orelse return;

        if (!keyboard_state.isDown(.left_shift)) {
            if (keyboard_state.isDown(.w)) {
                ship.applyInputThrust(&world.physics, .forward);
            }

            if (keyboard_state.isDown(.s)) {
                ship.applyInputThrust(&world.physics, .backward);
            }

            if (keyboard_state.isDown(.a)) {
                ship.applyInputThrust(&world.physics, .left);
            }

            if (keyboard_state.isDown(.d)) {
                ship.applyInputThrust(&world.physics, .right);
            }
        } else {
            if (keyboard_state.isDown(.w)) {
                ship.applyInputThrust(&world.physics, .secondary_forward);
            }

            if (keyboard_state.isDown(.s)) {
                ship.applyInputThrust(&world.physics, .secondary_backward);
            }

            if (keyboard_state.isDown(.a)) {
                ship.applyInputThrust(&world.physics, .secondary_left);
            }

            if (keyboard_state.isDown(.d)) {
                ship.applyInputThrust(&world.physics, .secondary_right);
            }
        }

        if (mouse_state.is_left_clicked) {
            const mouse_pos = mouse_state.getRelativePosition();
            const world_pos = world.camera.screenToWorld(mouse_pos);

            for (world.objects.items) |*object| {
                if (object.id == self.target_id) {
                    continue;
                }

                const coords = object.getTileCoordsAtWorldPos(world_pos) orelse continue;
                const tile = object.getTile(coords.x, coords.y) orelse continue;
                if (tile.data == .empty) continue;

                const target_pos = object.getTileWorldPos(coords.x, coords.y);

                const tile_refs = try ship.getTilesByPartKind(.laser);
                defer self.allocator.free(tile_refs);

                const LaserCandidate = struct {
                    coords: TileCoords,
                    dist: f32,
                    tier: u8,
                };
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
                        const tier = ti.getTier() orelse continue;

                        const range = PartStats.getLaserRangeSq(tier);
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
                            .tier = tier,
                        });
                    }
                }

                if (laser_candidates.items.len == 0) {
                    std.debug.print("No valid laser avaiable for mining\n", .{});
                    break;
                }

                // get closest laser
                const best_candidate = find_min: {
                    var min: ?LaserCandidate = null;

                    for (laser_candidates.items) |candidate| {
                        if (min == null or candidate.dist < min.?.dist) {
                            min = candidate;
                        }
                    }

                    break :find_min min;
                };

                if (best_candidate == null) {
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
                        const resource_amounts = tile.data.terrain.resources;

                        for (resource_amounts.slice()) |res_amount| {
                            const cargo_list = try ship.getTilesByPartKindSortedByDist(.cargo, ship.position);

                            var prng = std.Random.DefaultPrng.init(blk: {
                                var seed: u64 = undefined;
                                try std.posix.getrandom(std.mem.asBytes(&seed));
                                break :blk seed;
                            });
                            const rand = prng.random();

                            var remaining = rand.intRangeAtMost(
                                u8,
                                0,
                                res_amount.amount,
                            );

                            for (cargo_list) |cargo| {
                                const inventory = ship.getInventory(cargo.tile_x, cargo.tile_y) orelse try ship.addInventory(cargo.tile_x, cargo.tile_y, 20);

                                const result = try inventory.add(.{ .resource = res_amount.resource }, remaining);
                                remaining = @intCast(result.remaining);

                                if (result.added > 0) {
                                    _ = world.research_manager.reportResourcePickup(res_amount.resource, result.added);
                                }

                                if (remaining == 0) {
                                    break;
                                }
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

                                        // Add random drift
                                        const rand = std.crypto.random;
                                        const drift_speed = 30.0;
                                        final_vel.x += (rand.float(f32) - 0.5) * drift_speed;
                                        final_vel.y += (rand.float(f32) - 0.5) * drift_speed;

                                        // Add random rotation
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
                                target_obj_refreshed.physics_dirty = true;
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
            TileAction.init(.mine, source, target, 1.0),
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
