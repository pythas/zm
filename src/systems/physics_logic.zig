const std = @import("std");
const Vec2 = @import("../vec2.zig").Vec2;
const TileObject = @import("../tile_object.zig").TileObject;
const Physics = @import("../box2d_physics.zig").Physics;
const InputState = @import("../input.zig").InputState;
const PartStats = @import("../ship.zig").PartStats;
const PartModule = @import("../tile.zig").PartModule;
const Direction = @import("../tile.zig").Direction;
const BodyId = @import("../box2d_physics.zig").BodyId;
const PhysicsTileData = @import("../box2d_physics.zig").TileData;
const config = @import("../config.zig");

pub const PhysicsLogic = struct {
    pub fn applyInputTorque(ship: *TileObject, physics: *Physics, input: InputState) void {
        if (!ship.body_id.isValid()) {
            return;
        }

        const torque_power: f32 = 1_000_000.0;

        switch (input) {
            .rotate_cw => {
                physics.addTorque(ship.body_id, torque_power, true);
            },
            .rotate_ccw => {
                physics.addTorque(ship.body_id, -torque_power, true);
            },
            else => {},
        }
    }

    pub fn applyInputThrust(ship: *TileObject, physics: *Physics, input: InputState) void {
        if (!ship.body_id.isValid()) {
            return;
        }

        const body_pos = physics.getPosition(ship.body_id);
        const body_rot = physics.getRotation(ship.body_id);

        const cos_rot = @cos(body_rot);
        const sin_rot = @sin(body_rot);

        for (ship.thrusters.items) |*thruster| {
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

                physics.addForceAtPoint(ship.body_id, force, apply_point, true);
            }
        }
    }

    pub fn stabilize(ship: *TileObject, physics: *Physics, linear: bool) void {
        if (!ship.body_id.isValid()) return;

        if (linear) {
            const vel = physics.getLinearVelocity(ship.body_id);

            if (vel.lengthSq() > 0.1) {
                const rot = physics.getRotation(ship.body_id);
                const cos = @cos(-rot);
                const sin = @sin(-rot);

                // transform velocity to local space
                const local_vel = Vec2.init(
                    vel.x * cos - vel.y * sin,
                    vel.x * sin + vel.y * cos,
                );

                const threshold = 20;

                if (local_vel.y > threshold) applyInputThrust(ship, physics, .forward);
                if (local_vel.y < -threshold) applyInputThrust(ship, physics, .backward);
                if (local_vel.x > threshold) applyInputThrust(ship, physics, .left);
                if (local_vel.x < -threshold) applyInputThrust(ship, physics, .right);
            }
        }
    }

    pub fn recalculatePhysics(ship: *TileObject, physics: *Physics) !void {
        var linear_velocity = Vec2.init(0, 0);
        var angular_velocity: f32 = 0.0;

        const terrain_density = 10.0; // TODO: should be based on terrain type

        if (ship.body_id.isValid()) {
            ship.position = physics.getPosition(ship.body_id);
            ship.rotation = physics.getRotation(ship.body_id);

            linear_velocity = physics.getLinearVelocity(ship.body_id);
            angular_velocity = physics.getAngularVelocity(ship.body_id);

            physics.destroyBody(ship.body_id);
            ship.body_id = BodyId.invalid;
        }

        var physics_tiles = std.ArrayList(PhysicsTileData).init(ship.allocator);
        defer physics_tiles.deinit();

        const visited = try ship.allocator.alloc(bool, ship.width * ship.height);
        defer ship.allocator.free(visited);
        @memset(visited, false);

        for (0..ship.height) |y| {
            for (0..ship.width) |x| {
                if (visited[y * ship.width + x]) {
                    continue;
                }

                const tile = ship.getTile(x, y) orelse continue;
                const density: f32 = switch (tile.data) {
                    .ship_part => |ship_data| PartStats.getDensity(ship_data.kind),
                    .terrain => terrain_density,
                    .empty => 0.0,
                };

                if (density == 0.0) {
                    continue;
                }

                // greedy meshing
                var w: usize = 1;
                var h: usize = 1;

                // expand horizontal
                while (x + w < ship.width) : (w += 1) {
                    if (visited[y * ship.width + (x + w)]) break;

                    const next_tile = ship.getTile(x + w, y) orelse break;
                    const next_density: f32 = switch (next_tile.data) {
                        .ship_part => |ship_data| PartStats.getDensity(ship_data.kind),
                        .terrain => terrain_density,
                        .empty => 0.0,
                    };

                    if (next_density != density) break;
                }

                // expand vertical
                can_expand_h: while (y + h < ship.height) : (h += 1) {
                    for (0..w) |dx| {
                        if (visited[(y + h) * ship.width + (x + dx)]) break :can_expand_h;

                        const next_tile = ship.getTile(x + dx, y + h) orelse break :can_expand_h;
                        const next_density: f32 = switch (next_tile.data) {
                            .ship_part => |ship_data| PartStats.getDensity(ship_data.kind),
                            .terrain => terrain_density,
                            .empty => 0.0,
                        };

                        if (next_density != density) break :can_expand_h;
                    }
                }

                // mark visited
                for (0..h) |dy| {
                    for (0..w) |dx| {
                        visited[(y + dy) * ship.width + (x + dx)] = true;
                    }
                }

                const object_center_x = @as(f32, @floatFromInt(ship.width)) * 4.0;
                const object_center_y = @as(f32, @floatFromInt(ship.height)) * 4.0;

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
                    .layer = if (ship.object_type == .debris) .debris else .default,
                });
            }
        }

        if (physics_tiles.items.len == 0) {
            return;
        }

        var linear_damping: f32 = 0.0;
        var angular_damping: f32 = 0.0;

        if (ship.object_type == .ship_part) {
            linear_damping = config.physics.linear_damping;
            angular_damping = config.physics.angular_damping;
        }

        ship.body_id = try physics.createBody(
            ship.position,
            ship.rotation,
            linear_damping,
            angular_damping,
        );

        try physics.createTileShape(ship.body_id, physics_tiles.items);

        physics.setLinearVelocity(ship.body_id, linear_velocity);
        physics.setAngularVelocity(ship.body_id, angular_velocity);

        try rebuildThrusters(ship);
    }

    pub fn rebuildThrusters(ship: *TileObject) !void {
        ship.thrusters.clearRetainingCapacity();

        if (ship.object_type != .ship_part and ship.object_type != .enemy_drone) {
            return;
        }

        for (0..ship.width) |x| {
            for (0..ship.height) |y| {
                const tile = ship.getTile(x, y) orelse continue;
                const ship_part = tile.getShipPart() orelse continue;

                if (ship_part.kind == .chemical_thruster) {
                    var power = PartStats.getEnginePower(ship_part.tier);
                    if (PartStats.isBroken(ship_part)) {
                        power *= 0.1;
                    }

                    const object_center_x = @as(f32, @floatFromInt(ship.width)) * 4.0;
                    const object_center_y = @as(f32, @floatFromInt(ship.height)) * 4.0;
                    const local_x = @as(f32, @floatFromInt(x)) * 8.0 + 4.0 - object_center_x;
                    const local_y = @as(f32, @floatFromInt(y)) * 8.0 + 4.0 - object_center_y;

                    try ship.thrusters.append(.{
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

                    const object_center_x = @as(f32, @floatFromInt(ship.width)) * 4.0;
                    const object_center_y = @as(f32, @floatFromInt(ship.height)) * 4.0;
                    const local_x = @as(f32, @floatFromInt(x)) * 8.0 + 4.0 - object_center_x;
                    const local_y = @as(f32, @floatFromInt(y)) * 8.0 + 4.0 - object_center_y;

                    // smart_core thrusters are omnidirectional
                    const directions = [_]Direction{ .north, .east, .south, .west };
                    for (directions) |dir| {
                        try ship.thrusters.append(.{
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
