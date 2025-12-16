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
const ShipPart = @import("tile.zig").ShipPart; // Renamed from ItemId

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
                ship.applyInputThrust(&world.physics, .Forward);
            }

            if (keyboard_state.isDown(.s)) {
                ship.applyInputThrust(&world.physics, .Backward);
            }

            if (keyboard_state.isDown(.a)) {
                ship.applyInputThrust(&world.physics, .Left);
            }

            if (keyboard_state.isDown(.d)) {
                ship.applyInputThrust(&world.physics, .Right);
            }
        } else {
            if (keyboard_state.isDown(.w)) {
                ship.applyInputThrust(&world.physics, .SecondaryForward);
            }

            if (keyboard_state.isDown(.s)) {
                ship.applyInputThrust(&world.physics, .SecondaryBackward);
            }

            if (keyboard_state.isDown(.a)) {
                ship.applyInputThrust(&world.physics, .SecondaryLeft);
            }

            if (keyboard_state.isDown(.d)) {
                ship.applyInputThrust(&world.physics, .SecondaryRight);
            }
        }

        if (mouse_state.is_left_clicked) {
            const mouse_pos = mouse_state.getRelativePosition();
            const world_pos = world.camera.screenToWorld(mouse_pos);

            for (world.objects.items) |*object| {
                if (object.id == self.target_id) {
                    continue;
                }

                if (object.getTileCoordsAtWorldPos(world_pos)) |coords| {
                    if (object.getTile(coords.x, coords.y)) |tile| {
                        if (tile.data == .Empty) {
                            break;
                        }

                        const target_pos = object.getTileWorldPos(coords.x, coords.y);

                        const tile_refs = try ship.getTileByShipPart(.Laser);
                        defer self.allocator.free(tile_refs);

                        // get all available lasers
                        var laser_candidates = std.ArrayList(struct {
                            coords: TileCoords,
                            dist: f32,
                        }).init(self.allocator);
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
                                try laser_candidates.append(.{
                                    .coords = .{
                                        .x = tile_ref.tile_x,
                                        .y = tile_ref.tile_y,
                                    },
                                    .dist = ship.getDistanceToTileSq(
                                        tile_ref.tile_x,
                                        tile_ref.tile_y,
                                        target_pos,
                                    ),
                                });
                            }
                        }

                        if (laser_candidates.items.len == 0) {
                            std.debug.print("No valid laser avaiable for mining\n", .{});
                            break;
                        }

                        // get closest laser
                        var source: ?TileCoords = null;
                        var d_min: ?f32 = null;

                        for (laser_candidates.items) |laser_candidate| {
                            if (d_min == null or laser_candidate.dist < d_min.?) {
                                d_min = laser_candidate.dist;
                                source = laser_candidate.coords;
                            }
                        }

                        if (source == null) {
                            break;
                        }

                        // TODO: check if laser are in dist

                        const target = TileReference{
                            .object_id = object.id,
                            .tile_x = coords.x,
                            .tile_y = coords.y,
                        };

                        try self.startMining(source.?, target);

                        break;
                    }
                }
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
                    .Mine => {
                        std.debug.print("mine tile: {d} {d}\n", .{
                            tile_action.target.tile_x,
                            tile_action.target.tile_y,
                        });

                        if (world.getObjectById(tile_action.target.object_id)) |target_obj| {
                            const tx = tile_action.target.tile_x;
                            const ty = tile_action.target.tile_y;
                            const target_id = tile_action.target.object_id;

                            if (target_obj.getTile(tx, ty)) |tile| {
                                if (tile.data != .Empty) {
                                    const debris_pos = target_obj.getTileWorldPos(tx, ty);

                                    const new_id = world.generateObjectId();
                                    var debris = try TileObject.init(self.allocator, new_id, 1, 1, debris_pos, target_obj.rotation);
                                    debris.object_type = .Debris;
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
            TileAction.init(.Mine, source, target, 3.0),
        );
    }
};

pub const TileAction = struct {
    const Self = @This();

    pub const Kind = enum {
        Mine,
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
