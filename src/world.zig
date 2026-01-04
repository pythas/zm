const std = @import("std");
const math = std.math;
const zglfw = @import("zglfw");

const Physics = @import("box2d_physics.zig").Physics;
const KeyboardState = @import("input.zig").KeyboardState;
const MouseState = @import("input.zig").MouseState;
const PlayerController = @import("player.zig").PlayerController;
const ResearchManager = @import("research.zig").ResearchManager;
const NotificationSystem = @import("notification.zig").NotificationSystem;
const Camera = @import("camera.zig").Camera;
const Vec2 = @import("vec2.zig").Vec2;
const Tile = @import("tile.zig").Tile;
const PartModule = @import("tile.zig").PartModule;
const Direction = @import("tile.zig").Direction;
const TileObject = @import("tile_object.zig").TileObject;
const ship_serialization = @import("ship_serialization.zig");
const AsteroidGenerator = @import("asteroid_generator.zig").AsteroidGenerator;
const Resource = @import("resource.zig").Resource;
const WorldGen = @import("world_gen.zig");
const WorldGenerator = WorldGen.WorldGenerator;
const SectorConfig = WorldGen.SectorConfig;
const SectorType = WorldGen.SectorType;
const rng = @import("rng.zig");
const RailgunTrail = @import("effects.zig").RailgunTrail;
const LaserBeam = @import("effects.zig").LaserBeam;
const AiController = @import("ai_controller.zig").AiController;

pub const ChunkCoord = struct {
    x: i32,
    y: i32,
};

pub const World = struct {
    const Self = @This();
    const chunkSize = 512.0;

    allocator: std.mem.Allocator,

    camera: Camera,
    player_controller: PlayerController,
    ai_controller: AiController,
    research_manager: ResearchManager,
    notifications: NotificationSystem,

    next_object_id: u64 = 0,
    objects: std.ArrayList(TileObject),
    railgun_trails: std.ArrayList(RailgunTrail),
    laser_beams: std.ArrayList(LaserBeam),

    physics: Physics,

    // world generation
    world_generator: WorldGenerator,
    sector_config: SectorConfig,
    generated_chunks: std.AutoHashMap(ChunkCoord, void),

    pub fn init(allocator: std.mem.Allocator) !Self {
        var physics = try Physics.init(allocator);

        const camera = Camera.init(
            Vec2.init(0, 0),
        );

        const player_controller = PlayerController.init(allocator, 0);
        const ai_controller = AiController.init(allocator);
        const notifications = NotificationSystem.init(allocator);
        const world_generator = WorldGenerator.init(12345); // TODO: load from settings
        const sector_config = SectorConfig{
            .seed = 12345,
            .sector_type = .cradle,
        };

        var self: Self = .{
            .allocator = allocator,
            .camera = camera,
            .objects = std.ArrayList(TileObject).init(allocator),
            .railgun_trails = std.ArrayList(RailgunTrail).init(allocator),
            .laser_beams = std.ArrayList(LaserBeam).init(allocator),
            .player_controller = player_controller,
            .ai_controller = ai_controller,
            .research_manager = ResearchManager.init(),
            .notifications = notifications,
            .physics = physics,
            .world_generator = world_generator,
            .sector_config = sector_config,
            .generated_chunks = std.AutoHashMap(ChunkCoord, void).init(allocator),
        };

        const ship_id = self.generateObjectId();
        var ship = ship_serialization.loadShip(allocator, ship_id, "assets/ship.json") catch |err| switch (err) {
            error.FileNotFound => try TileObject.init(allocator, ship_id, 16, 16, Vec2.init(0, 0), 0),
            else => return err,
        };

        ship.object_type = .ship_part;

        try ship.recalculatePhysics(&physics);
        try ship.initInventories();
        try self.objects.append(ship);

        // tmp: spawn a test drone nearby
        // try self.spawnEnemyDrone(Vec2.init(0, -100));

        try self.updateWorldGeneration(Vec2.init(0, 0));

        return self;
    }

    pub fn deinit(self: *Self) void {
        for (self.objects.items) |*obj| {
            obj.deinit();
        }
        self.objects.deinit();
        self.railgun_trails.deinit();
        self.laser_beams.deinit();
        self.physics.deinit();
        self.player_controller.deinit();
        self.ai_controller.deinit();
        self.notifications.deinit();
        self.generated_chunks.deinit();
    }

    pub fn generateObjectId(self: *Self) u64 {
        const id = self.next_object_id;

        self.next_object_id += 1;

        return id;
    }

    pub fn getObjectById(self: *World, id: u64) ?*TileObject {
        for (self.objects.items) |*obj| {
            if (obj.id == id) {
                return obj;
            }
        }

        return null;
    }

    pub fn update(
        self: *Self,
        dt: f32,
        keyboard_state: *const KeyboardState,
        mouse_state: *const MouseState,
    ) !void {
        self.physics.update(dt);
        self.notifications.update(dt);

        var i: usize = 0;
        while (i < self.railgun_trails.items.len) {
            var trail = &self.railgun_trails.items[i];
            trail.lifetime -= dt;

            if (trail.lifetime <= 0) {
                _ = self.railgun_trails.swapRemove(i);
            } else {
                i += 1;
            }
        }

        i = 0;
        while (i < self.laser_beams.items.len) {
            var beam = &self.laser_beams.items[i];
            beam.lifetime -= dt;

            if (beam.lifetime <= 0) {
                _ = self.laser_beams.swapRemove(i);
            } else {
                i += 1;
            }
        }

        for (self.objects.items) |*obj| {
            if (!obj.body_id.isValid()) {
                continue;
            }

            obj.updateThrusterVisuals(dt);

            const pos = self.physics.getPosition(obj.body_id);
            const rot = self.physics.getRotation(obj.body_id);

            obj.position = pos;
            obj.rotation = rot;
        }

        try self.ai_controller.update(dt, self);

        try self.player_controller.update(
            dt,
            self,
            keyboard_state,
            mouse_state,
        );

        if (self.objects.items.len > 0) {
            try self.updateWorldGeneration(self.objects.items[0].position);
        }

        var new_objects_list = std.ArrayList(TileObject).init(self.allocator);
        defer new_objects_list.deinit();

        for (self.objects.items) |*obj| {
            if (!obj.body_id.isValid()) {
                continue;
            }

            if (obj.dirty) {
                const result_opt = try obj.checkSplit(self.allocator, self, struct {
                    fn gen(ctx: *World) u64 {
                        return ctx.generateObjectId();
                    }
                }.gen);

                if (result_opt) |result| {
                    var list = result;
                    defer list.deinit();
                    try new_objects_list.appendSlice(list.items);
                }

                try obj.recalculatePhysics(&self.physics);
            }

            const pos = self.physics.getPosition(obj.body_id);
            const rot = self.physics.getRotation(obj.body_id);

            obj.position = pos;
            obj.rotation = rot;
        }

        for (new_objects_list.items) |*new_obj| {
            try new_obj.recalculatePhysics(&self.physics);
            try self.objects.append(new_obj.*);
        }

        // cleanup dead objects (no tiles)
        var obj_idx: usize = 0;
        while (obj_idx < self.objects.items.len) {
            const obj = &self.objects.items[obj_idx];

            var has_tiles = false;
            for (obj.tiles) |tile| {
                if (tile.data != .empty) {
                    has_tiles = true;
                    break;
                }
            }

            if (!has_tiles and obj.id != 0) {
                self.physics.destroyBody(obj.body_id);
                obj.deinit();
                _ = self.objects.swapRemove(obj_idx);
            } else {
                obj_idx += 1;
            }
        }

        if (self.objects.items.len > 0) {
            self.camera.position = self.objects.items[0].position;
        }
    }

    fn updateWorldGeneration(self: *Self, pos: Vec2) !void {
        const chunk_x = @as(i32, @intFromFloat(math.floor(pos.x / chunkSize)));
        const chunk_y = @as(i32, @intFromFloat(math.floor(pos.y / chunkSize)));
        const range = 4;

        var y = chunk_y - range;
        while (y <= chunk_y + range) : (y += 1) {
            var x = chunk_x - range;
            while (x <= chunk_x + range) : (x += 1) {
                const coord = ChunkCoord{ .x = x, .y = y };

                if (!self.generated_chunks.contains(coord)) {
                    try self.generateChunk(coord);
                    try self.generated_chunks.put(coord, {});
                }
            }
        }

        self.unloadFarChunks(pos);
    }

    fn unloadFarChunks(self: *Self, player_pos: Vec2) void {
        const unload_dist = chunkSize * 6.0;
        const unload_dist_sq = unload_dist * unload_dist;

        var i: usize = self.objects.items.len;
        while (i > 1) {
            i -= 1;
            const obj = &self.objects.items[i];

            const dx = obj.position.x - player_pos.x;
            const dy = obj.position.y - player_pos.y;
            const dist_sq = dx * dx + dy * dy;

            if (dist_sq > unload_dist_sq) {
                const chunk_x = @as(i32, @intFromFloat(math.floor(obj.position.x / chunkSize)));
                const chunk_y = @as(i32, @intFromFloat(math.floor(obj.position.y / chunkSize)));
                const coord = ChunkCoord{ .x = chunk_x, .y = chunk_y };

                // TODO: we should probably persist it so we can regenerate the chunk later
                _ = self.generated_chunks.remove(coord);

                self.physics.destroyBody(obj.body_id);
                obj.deinit();
                _ = self.objects.swapRemove(i);
            }
        }
    }

    fn generateChunk(self: *Self, coord: ChunkCoord) !void {
        const chunk_world_x = @as(f32, @floatFromInt(coord.x)) * chunkSize;
        const chunk_world_y = @as(f32, @floatFromInt(coord.y)) * chunkSize;
        const center = Vec2.init(chunk_world_x + chunkSize * 0.5, chunk_world_y + chunkSize * 0.5);

        // safe zone
        if (center.length() < 200.0) {
            return;
        }

        const zone = self.sector_config.getZone(center);
        const rules = WorldGenerator.getRules(self.sector_config.sector_type, zone);

        if (self.world_generator.shouldSpawnAsteroid(coord.x, coord.y, rules.density)) {
            const rand = rng.random();
            const width_range = rules.max_size - rules.min_size;

            const w = rules.min_size + rand.uintAtMost(usize, width_range);
            const h = rules.min_size + rand.uintAtMost(usize, width_range);

            const jitter_x = rand.float(f32) * (chunkSize * 0.6) + (chunkSize * 0.2);
            const jitter_y = rand.float(f32) * (chunkSize * 0.6) + (chunkSize * 0.2);
            const spawn_pos = Vec2.init(chunk_world_x + jitter_x, chunk_world_y + jitter_y);

            var resources = try std.ArrayList(AsteroidGenerator.ResourceConfig).initCapacity(self.allocator, 5);
            defer resources.deinit();

            if (rules.iron_prob > 0) resources.appendAssumeCapacity(.{ .resource = .iron, .probability = rules.iron_prob, .min_amount = 2, .max_amount = 10 });
            if (rules.carbon_prob > 0) resources.appendAssumeCapacity(.{ .resource = .carbon, .probability = rules.carbon_prob, .min_amount = 2, .max_amount = 10 });
            if (rules.copper_prob > 0) resources.appendAssumeCapacity(.{ .resource = .copper, .probability = rules.copper_prob, .min_amount = 2, .max_amount = 8 });
            if (rules.gold_prob > 0) resources.appendAssumeCapacity(.{ .resource = .gold, .probability = rules.gold_prob, .min_amount = 1, .max_amount = 5 });
            if (rules.uranium_prob > 0) resources.appendAssumeCapacity(.{ .resource = .uranium, .probability = rules.uranium_prob, .min_amount = 1, .max_amount = 3 });

            const variant = rand.uintAtMost(u8, 3);

            var asteroid = try AsteroidGenerator.createAsteroid(
                self.allocator,
                self.generateObjectId(),
                spawn_pos,
                w,
                h,
                .irregular,
                variant,
                resources.items,
            );

            try asteroid.recalculatePhysics(&self.physics);

            // add initial motion
            const vel_x = (rand.float(f32) - 0.5) * 10.0;
            const vel_y = (rand.float(f32) - 0.5) * 10.0;
            const ang_vel = (rand.float(f32) - 0.5) * 1.0;

            self.physics.setLinearVelocity(asteroid.body_id, Vec2.init(vel_x, vel_y));
            self.physics.setAngularVelocity(asteroid.body_id, ang_vel);

            try self.objects.append(asteroid);
        } else if (center.length() > 300.0 and rng.random().float(f32) < 0.05) {
            const jitter_x = (rng.random().float(f32) - 0.5) * chunkSize;
            const jitter_y = (rng.random().float(f32) - 0.5) * chunkSize;
            try self.spawnEnemyDrone(Vec2.init(center.x + jitter_x, center.y + jitter_y));
        }
    }

    pub fn onScroll(self: *Self, xoffset: f64, yoffset: f64) void {
        _ = xoffset;

        if (yoffset > 0) {
            self.camera.zoom *= 1.1;
        } else if (yoffset < 0) {
            self.camera.zoom *= 0.9;
        }

        self.camera.zoom = @max(0.2, @min(10.0, self.camera.zoom));
    }

    fn spawnEnemyDrone(self: *Self, position: Vec2) !void {
        const drone_id = self.generateObjectId();
        var drone = try TileObject.init(self.allocator, drone_id, 1, 1, position, 0);
        drone.object_type = .enemy_drone;

        const modules = PartModule.thruster | PartModule.laser | PartModule.shield | PartModule.reactor;

        const core_tile = Tile{
            .data = .{
                .ship_part = .{
                    .kind = .smart_core,
                    .tier = 4,
                    .health = 50.0,
                    .rotation = null,
                    .modules = modules,
                },
            },
        };

        drone.setTile(0, 0, core_tile);
        try drone.recalculatePhysics(&self.physics);

        try self.objects.append(drone);
    }
};

pub fn scrollCallback(window: *zglfw.Window, xoffset: f64, yoffset: f64) callconv(.c) void {
    const world = zglfw.getWindowUserPointer(window, World) orelse return;

    world.onScroll(xoffset, yoffset);
}
