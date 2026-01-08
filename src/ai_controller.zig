const std = @import("std");

const Vec2 = @import("vec2.zig").Vec2;
const TileObject = @import("tile_object.zig").TileObject;
const World = @import("world.zig").World;
const PartStats = @import("ship.zig").PartStats;
const PhysicsLogic = @import("systems/physics_logic.zig").PhysicsLogic;
const InputState = @import("input.zig").InputState;
const PartKind = @import("tile.zig").PartKind;
const rng = @import("rng.zig");
const TileReference = @import("tile.zig").TileReference;
const config = @import("config.zig");

const DroneState = struct {
    mode: enum { idle, combat } = .idle,
    orbit_dir: f32 = 1.0,
    laser_cooldown: f32 = 0.0,
};

pub const AiController = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    drone_states: std.AutoHashMap(u64, DroneState),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .drone_states = std.AutoHashMap(u64, DroneState).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.drone_states.deinit();
    }

    pub fn update(self: *Self, dt: f32, world: *World) !void {
        if (world.objects.items.len == 0) return;

        const player = &world.objects.items[0];
        const player_pos = player.position;

        // clean up states
        var it = self.drone_states.keyIterator();
        while (it.next()) |key| {
            if (world.getObjectById(key.*) == null) {
                _ = self.drone_states.remove(key.*);
            }
        }

        for (world.objects.items) |*obj| {
            if (obj.object_type != .enemy_drone) continue;
            if (!obj.body_id.isValid()) continue;

            const res = try self.drone_states.getOrPut(obj.id);
            if (!res.found_existing) {
                res.value_ptr.* = DroneState{
                    .orbit_dir = if (rng.random().boolean()) 1.0 else -1.0,
                };
            }

            try self.updateDrone(dt, world, obj, player_pos, res.value_ptr);
        }
    }

    fn updateDrone(
        self: *Self,
        dt: f32,
        world: *World,
        drone: *TileObject,
        target_pos: Vec2,
        state: *DroneState,
    ) !void {
        const diff = target_pos.sub(drone.position);
        const dist = diff.length();
        if (dist < 0.001) return;

        // cctivation
        if (state.mode == .idle) {
            if (dist < 400.0) state.mode = .combat;
            return;
        }

        // rotation & ,ovement
        self.updateRotation(world, drone, diff);
        try self.updateMovement(world, drone, diff, state);

        // combat
        if (state.laser_cooldown > 0.0) {
            state.laser_cooldown -= dt;
        }

        // only fire if facing the player
        const dir = diff.normalize();
        const math_angle = std.math.atan2(dir.y, dir.x);
        const target_angle = math_angle + std.math.pi / 2.0;
        var angle_diff = target_angle - drone.rotation;
        while (angle_diff > std.math.pi) angle_diff -= 2.0 * std.math.pi;
        while (angle_diff < -std.math.pi) angle_diff += 2.0 * std.math.pi;

        if (@abs(angle_diff) < 0.5) {
            try self.droneFireWeapons(world, drone, target_pos, state);
        }
    }

    fn updateRotation(self: *Self, world: *World, drone: *TileObject, diff_to_target: Vec2) void {
        _ = self;
        const dir = diff_to_target.normalize();
        const math_angle = std.math.atan2(dir.y, dir.x);
        const target_angle = math_angle + std.math.pi / 2.0;

        var angle_diff = target_angle - drone.rotation;
        while (angle_diff > std.math.pi) angle_diff -= 2.0 * std.math.pi;
        while (angle_diff < -std.math.pi) angle_diff += 2.0 * std.math.pi;

        world.physics.setAngularVelocity(drone.body_id, angle_diff * 5.0);
    }

    fn updateMovement(
        self: *Self,
        world: *World,
        drone: *TileObject,
        diff_to_target: Vec2,
        state: *DroneState,
    ) !void {
        const dist = diff_to_target.length();
        const dir = diff_to_target.normalize();

        const target_radius = 120.0;
        const tangent = Vec2.init(-dir.y, dir.x).mulScalar(state.orbit_dir);

        // correction vector
        const correction_strength = (dist - target_radius) * 0.05;
        const move_vec = tangent.add(dir.mulScalar(correction_strength));

        try self.applyWorldDirectionThrust(world, drone, move_vec.normalize());
    }

    fn applyWorldDirectionThrust(
        self: *Self,
        world: *World,
        drone: *TileObject,
        world_dir: Vec2,
    ) !void {
        _ = self;
        const cos_rot = @cos(-drone.rotation);
        const sin_rot = @sin(-drone.rotation);

        const local_x = world_dir.x * cos_rot - world_dir.y * sin_rot;
        const local_y = world_dir.x * sin_rot + world_dir.y * cos_rot;

        if (local_y < -0.2) PhysicsLogic.applyInputThrust(drone, &world.physics, .forward);
        if (local_y > 0.2) PhysicsLogic.applyInputThrust(drone, &world.physics, .backward);
        if (local_x > 0.2) PhysicsLogic.applyInputThrust(drone, &world.physics, .right);
        if (local_x < -0.2) PhysicsLogic.applyInputThrust(drone, &world.physics, .left);
    }

    fn droneFireWeapons(
        self: *Self,
        world: *World,
        drone: *TileObject,
        target_pos: Vec2,
        state: *DroneState,
    ) !void {
        if (state.laser_cooldown > 0.0) return;

        const lasers = try drone.getTilesByPartKind(.laser);
        defer self.allocator.free(lasers);

        if (lasers.len == 0) return;

        const player_ship = &world.objects.items[0];
        const target_tile_world_pos = try self.findTargetTile(player_ship);

        // fire all lasers
        for (lasers) |ref| {
            try self.fireLaser(world, drone, ref, target_pos, player_ship, target_tile_world_pos);
        }

        state.laser_cooldown = config.combat.laser_cooldown;
    }

    fn findTargetTile(self: *Self, ship: *TileObject) !Vec2 {
        // try to find a reactor
        const reactors = try ship.getTilesByPartKind(.reactor);
        defer self.allocator.free(reactors);

        if (reactors.len > 0) {
            const idx = rng.random().uintAtMost(usize, reactors.len - 1);
            const ref = reactors[idx];

            return ship.getTileWorldPos(ref.tile_x, ref.tile_y);
        }

        // pick random part
        const w = ship.width;
        const h = ship.height;
        for (0..10) |_| {
            const tx = rng.random().uintAtMost(usize, w - 1);
            const ty = rng.random().uintAtMost(usize, h - 1);
            const tile = ship.getTile(tx, ty);

            if (tile != null and tile.?.data != .empty) {
                return ship.getTileWorldPos(tx, ty);
            }
        }

        // fallback to center
        return ship.position;
    }

    fn fireLaser(
        self: *Self,
        world: *World,
        drone: *TileObject,
        laser_ref: TileReference,
        target_pos: Vec2,
        player_ship: *TileObject,
        intended_target_pos: Vec2,
    ) !void {
        const tile = drone.getTile(laser_ref.tile_x, laser_ref.tile_y) orelse return;
        const part = tile.getShipPart() orelse return;
        const is_broken = PartStats.isBroken(part);

        const range_sq = PartStats.getLaserRangeSq(part.tier, is_broken);
        const dist_sq = drone.getDistanceToTileSq(laser_ref.tile_x, laser_ref.tile_y, target_pos);

        if (dist_sq < range_sq) {
            const laser_start = drone.getTileWorldPos(laser_ref.tile_x, laser_ref.tile_y);
            const damage = PartStats.getLaserDamage(part.tier);

            const actual_hit = self.performLaserRaycast(player_ship, laser_start, intended_target_pos, damage);

            // add visual beam
            try world.laser_beams.append(.{
                .start = laser_start,
                .end = actual_hit,
                .lifetime = 0.2,
                .max_lifetime = 0.2,
                .color = .{ 1.0, 0.2, 0.2, 1.0 },
            });
        }
    }

    fn performLaserRaycast(
        self: *Self,
        ship: *TileObject,
        start: Vec2,
        end: Vec2,
        damage: f32,
    ) Vec2 {
        _ = self;
        var actual_hit = end;
        const diff = end.sub(start);
                const dist = diff.length();
                const dir = diff.normalize();
        
                // step size from config
                var d: f32 = 0.0;
                while (d < dist) : (d += config.combat.laser_raycast_step) {
                    const test_pt = start.add(dir.mulScalar(d));
            if (ship.getTileCoordsAtWorldPos(test_pt)) |coords| {
                if (ship.getTile(coords.x, coords.y)) |hit_tile| {
                    if (hit_tile.data != .empty) {
                        actual_hit = ship.getTileWorldPos(coords.x, coords.y);
                        applyDamage(ship, hit_tile, coords.x, coords.y, damage);
                        break;
                    }
                }
            }
        }
        return actual_hit;
    }

    fn applyDamage(ship: *TileObject, tile: *std.meta.Child(@TypeOf(ship.tiles)), x: usize, y: usize, damage: f32) void {
        const current_health = tile.getHealth() orelse 0.0;

        if (current_health <= damage) {
            ship.setEmptyTile(x, y);
            ship.dirty = true;
        } else {
            switch (tile.data) {
                .ship_part => |*p| p.health -= damage,
                .terrain => |*t| t.health -= damage,
                else => {},
            }
        }
    }
};

