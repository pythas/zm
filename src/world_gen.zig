const std = @import("std");
const znoise = @import("znoise");
const Vec2 = @import("vec2.zig").Vec2;
const Resource = @import("resource.zig").Resource;
const AsteroidGenerator = @import("asteroid_generator.zig").AsteroidGenerator;
const rng = @import("rng.zig");
const TileObject = @import("tile_object.zig").TileObject;
const Tile = @import("tile.zig").Tile;
const PartModule = @import("tile.zig").PartModule;
const PhysicsLogic = @import("systems/physics_logic.zig").PhysicsLogic;
const config = @import("config.zig");

pub const SectorType = enum {
    cradle,
    forge,
    void,
};

pub const Zone = enum {
    safe, // 0-5
    periphery, // 5-25
    deep, // 25+
};

pub const ChunkCoord = struct {
    x: i32,
    y: i32,
};

pub const SectorConfig = struct {
    seed: i32,
    sector_type: SectorType,

    pub fn getZone(self: SectorConfig, pos: Vec2) Zone {
        _ = self;
        const dist = pos.length();
        if (dist < 5000.0) return .safe;
        if (dist < 25000.0) return .periphery;
        return .deep;
    }
};

pub const GenerationRules = struct {
    density: f32,
    min_size: usize,
    max_size: usize,

    iron_prob: f32,
    carbon_prob: f32,
    copper_prob: f32,
    gold_prob: f32,
    uranium_prob: f32,
};

pub const WorldGenerator = struct {
    const Self = @This();
    pub const chunkSize = 512.0;

    allocator: std.mem.Allocator,
    noise: znoise.FnlGenerator,
    sector_config: SectorConfig,
    generated_chunks: std.AutoHashMap(ChunkCoord, void),

    pub fn init(allocator: std.mem.Allocator, seed: i32) Self {
        const noise = znoise.FnlGenerator{
            .seed = seed,
            .noise_type = .opensimplex2,
            .frequency = 0.01,
        };
        const sector_config = SectorConfig{
            .seed = seed,
            .sector_type = .cradle,
        };
        return .{
            .allocator = allocator,
            .noise = noise,
            .sector_config = sector_config,
            .generated_chunks = std.AutoHashMap(ChunkCoord, void).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.generated_chunks.deinit();
    }

    pub fn shouldSpawnAsteroid(self: Self, chunk_x: i32, chunk_y: i32, density: f32) bool {
        var hasher = std.hash.Wyhash.init(0);
        hasher.update(std.mem.asBytes(&self.noise.seed));
        hasher.update(std.mem.asBytes(&chunk_x));
        hasher.update(std.mem.asBytes(&chunk_y));
        const hash = hasher.final();

        const val = @as(f32, @floatFromInt(hash % 10000)) / 10000.0;

        return val < density;
    }

    pub fn getRules(sector_type: SectorType, zone: Zone) GenerationRules {
        return switch (sector_type) {
            .cradle => switch (zone) {
                .safe => .{
                    .density = 0.6,
                    .min_size = 5,
                    .max_size = 12,
                    .iron_prob = 0.8,
                    .carbon_prob = 0.5,
                    .copper_prob = 0.1,
                    .gold_prob = 0.0,
                    .uranium_prob = 0.0,
                },
                .periphery => .{
                    .density = 0.4,
                    .min_size = 8,
                    .max_size = 20,
                    .iron_prob = 0.6,
                    .carbon_prob = 0.4,
                    .copper_prob = 0.3,
                    .gold_prob = 0.05,
                    .uranium_prob = 0.0,
                },
                .deep => .{
                    .density = 0.3,
                    .min_size = 15,
                    .max_size = 40,
                    .iron_prob = 0.4,
                    .carbon_prob = 0.3,
                    .copper_prob = 0.4,
                    .gold_prob = 0.1,
                    .uranium_prob = 0.05,
                },
            },
            .forge => switch (zone) {
                .safe => .{
                    .density = 0.5,
                    .min_size = 10,
                    .max_size = 20,
                    .iron_prob = 0.9,
                    .carbon_prob = 0.1,
                    .copper_prob = 0.4,
                    .gold_prob = 0.1,
                    .uranium_prob = 0.0,
                },
                .periphery => .{
                    .density = 0.7,
                    .min_size = 20,
                    .max_size = 50,
                    .iron_prob = 0.7,
                    .carbon_prob = 0.05,
                    .copper_prob = 0.6,
                    .gold_prob = 0.3,
                    .uranium_prob = 0.1,
                },
                .deep => .{
                    .density = 0.8,
                    .min_size = 40,
                    .max_size = 100,
                    .iron_prob = 0.5,
                    .carbon_prob = 0.0,
                    .copper_prob = 0.5,
                    .gold_prob = 0.5,
                    .uranium_prob = 0.2,
                },
            },
            .void => switch (zone) {
                .safe => .{
                    .density = 0.1,
                    .min_size = 5,
                    .max_size = 10,
                    .iron_prob = 0.2,
                    .carbon_prob = 0.8,
                    .copper_prob = 0.1,
                    .gold_prob = 0.0,
                    .uranium_prob = 0.0,
                },
                .periphery => .{
                    .density = 0.05,
                    .min_size = 30,
                    .max_size = 60,
                    .iron_prob = 0.1,
                    .carbon_prob = 0.5,
                    .copper_prob = 0.2,
                    .gold_prob = 0.1,
                    .uranium_prob = 0.2,
                },
                .deep => .{
                    .density = 0.02,
                    .min_size = 100,
                    .max_size = 300,
                    .iron_prob = 0.05,
                    .carbon_prob = 0.2,
                    .copper_prob = 0.1,
                    .gold_prob = 0.2,
                    .uranium_prob = 0.8,
                },
            },
        };
    }

    pub fn update(self: *Self, world: anytype, pos: Vec2) !void {
        const chunk_x = @as(i32, @intFromFloat(std.math.floor(pos.x / config.world.chunk_size)));
        const chunk_y = @as(i32, @intFromFloat(std.math.floor(pos.y / config.world.chunk_size)));
        const range = config.world.spawn_range_chunks;

        var y = chunk_y - range;
        while (y <= chunk_y + range) : (y += 1) {
            var x = chunk_x - range;
            while (x <= chunk_x + range) : (x += 1) {
                const coord = ChunkCoord{ .x = x, .y = y };

                if (!self.generated_chunks.contains(coord)) {
                    try self.generateChunk(world, coord);
                    try self.generated_chunks.put(coord, {});
                }
            }
        }

        self.unloadFarChunks(world, pos);
    }

    fn unloadFarChunks(self: *Self, world: anytype, player_pos: Vec2) void {
        const unload_dist = config.world.chunk_size * config.world.unload_dist_chunks;
        const unload_dist_sq = unload_dist * unload_dist;

        var i: usize = world.objects.items.len;
        while (i > 1) {
            i -= 1;
            const obj = &world.objects.items[i];

            const dx = obj.position.x - player_pos.x;
            const dy = obj.position.y - player_pos.y;
            const dist_sq = dx * dx + dy * dy;

            if (dist_sq > unload_dist_sq) {
                const chunk_x = @as(i32, @intFromFloat(std.math.floor(obj.position.x / config.world.chunk_size)));
                const chunk_y = @as(i32, @intFromFloat(std.math.floor(obj.position.y / config.world.chunk_size)));
                const coord = ChunkCoord{ .x = chunk_x, .y = chunk_y };

                // TODO: we should probably persist it so we can regenerate the chunk later
                _ = self.generated_chunks.remove(coord);

                world.physics.destroyBody(obj.body_id);
                obj.deinit();
                _ = world.objects.swapRemove(i);
            }
        }
    }

    fn generateChunk(self: *Self, world: anytype, coord: ChunkCoord) !void {
        const chunk_world_x = @as(f32, @floatFromInt(coord.x)) * config.world.chunk_size;
        const chunk_world_y = @as(f32, @floatFromInt(coord.y)) * config.world.chunk_size;
        const center = Vec2.init(chunk_world_x + config.world.chunk_size * 0.5, chunk_world_y + config.world.chunk_size * 0.5);

        // safe zone
        if (center.length() < 200.0) {
            return;
        }

        const zone = self.sector_config.getZone(center);
        const rules = Self.getRules(self.sector_config.sector_type, zone);

        if (self.shouldSpawnAsteroid(coord.x, coord.y, rules.density)) {
            const rand = rng.random();
            const width_range = rules.max_size - rules.min_size;

            const w = rules.min_size + rand.uintAtMost(usize, width_range);
            const h = rules.min_size + rand.uintAtMost(usize, width_range);

            const jitter_x = rand.float(f32) * (config.world.chunk_size * 0.6) + (config.world.chunk_size * 0.2);
            const jitter_y = rand.float(f32) * (config.world.chunk_size * 0.6) + (config.world.chunk_size * 0.2);
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
                world.generateObjectId(),
                spawn_pos,
                w,
                h,
                .irregular,
                variant,
                resources.items,
            );

            try PhysicsLogic.recalculatePhysics(&asteroid, &world.physics);

            // add initial motion
            // TODO: should be based on zones
            const vel_x = (rand.float(f32) - 0.5) * 40.0;
            const vel_y = (rand.float(f32) - 0.5) * 10.0;
            const ang_vel = (rand.float(f32) - 0.5) * 1.0;

            world.physics.setLinearVelocity(asteroid.body_id, Vec2.init(vel_x, vel_y));
            world.physics.setAngularVelocity(asteroid.body_id, ang_vel);

            try world.objects.append(asteroid);
        } else if (center.length() > 300.0 and rng.random().float(f32) < 0.05) {
            const jitter_x = (rng.random().float(f32) - 0.5) * config.world.chunk_size;
            const jitter_y = (rng.random().float(f32) - 0.5) * config.world.chunk_size;
            try self.spawnEnemyDrone(world, Vec2.init(center.x + jitter_x, center.y + jitter_y));
        }
    }

    fn spawnEnemyDrone(self: *Self, world: anytype, position: Vec2) !void {
        const drone_id = world.generateObjectId();
        var drone = try TileObject.init(self.allocator, drone_id, 1, 1, position, 0);
        drone.object_type = .enemy_drone;

        const modules = PartModule.thruster | PartModule.laser | PartModule.shield | PartModule.reactor;

        const core_tile = Tile.init(.{
            .ship_part = .{
                .kind = .smart_core,
                .tier = 4,
                .health = 50.0,
                .rotation = null,
                .modules = modules,
            },
        }) catch unreachable;

        drone.setTile(0, 0, core_tile);
        try PhysicsLogic.recalculatePhysics(&drone, &world.physics);

        try world.objects.append(drone);
    }
};

