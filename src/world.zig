const std = @import("std");
const math = std.math;
const zglfw = @import("zglfw");

const Physics = @import("box2d_physics.zig").Physics;
const KeyboardState = @import("input.zig").KeyboardState;
const MouseState = @import("input.zig").MouseState;
const PlayerController = @import("player.zig").PlayerController;
const ResearchManager = @import("research.zig").ResearchManager;
const Camera = @import("camera.zig").Camera;
const Vec2 = @import("vec2.zig").Vec2;
const Tile = @import("tile.zig").Tile;
const TileObject = @import("tile_object.zig").TileObject;
const ship_serialization = @import("ship_serialization.zig");
const AsteroidGenerator = @import("asteroid_generator.zig").AsteroidGenerator;
const Resource = @import("resource.zig").Resource;
const WorldGen = @import("world_gen.zig");
const WorldGenerator = WorldGen.WorldGenerator;
const SectorConfig = WorldGen.SectorConfig;
const SectorType = WorldGen.SectorType;
const rng = @import("rng.zig");

pub const ChunkCoord = struct {
    x: i32,
    y: i32,
};

pub const World = struct {
    const Self = @This();
    const CHUNK_SIZE = 512.0; // Size of a generation chunk in world units

    allocator: std.mem.Allocator,

    camera: Camera,
    player_controller: PlayerController,
    research_manager: ResearchManager,

    next_object_id: u64 = 0,
    objects: std.ArrayList(TileObject),

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
        const world_generator = WorldGenerator.init(12345); // TODO: load from settings
        const sector_config = SectorConfig{
            .seed = 12345,
            .sector_type = .cradle,
        };

        var self: Self = .{
            .allocator = allocator,
            .camera = camera,
            .objects = std.ArrayList(TileObject).init(allocator),
            .player_controller = player_controller,
            .research_manager = ResearchManager.init(),
            .physics = physics,
            .world_generator = world_generator,
            .sector_config = sector_config,
            .generated_chunks = std.AutoHashMap(ChunkCoord, void).init(allocator),
        };

        const ship_id = self.generateObjectId();
        var ship = ship_serialization.loadShip(allocator, ship_id, "ship.json") catch |err| switch (err) {
            error.FileNotFound => try TileObject.init(allocator, ship_id, 16, 16, Vec2.init(0, 0), 0),
            else => return err,
        };

        ship.object_type = .ship_part;
        try ship.recalculatePhysics(&physics);
        try self.objects.append(ship);

        try self.updateWorldGeneration(Vec2.init(0, 0));

        return self;
    }

    pub fn deinit(self: *Self) void {
        for (self.objects.items) |*obj| {
            obj.deinit();
        }
        self.objects.deinit();
        self.physics.deinit();
        self.player_controller.deinit();
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

        for (self.objects.items) |*obj| {
            if (!obj.body_id.isValid()) {
                continue;
            }

            const pos = self.physics.getPosition(obj.body_id);
            const rot = self.physics.getRotation(obj.body_id);

            obj.position = pos;
            obj.rotation = rot;
        }

        try self.player_controller.update(
            dt,
            self,
            keyboard_state,
            mouse_state,
        );

        if (self.objects.items.len > 0) {
            try self.updateWorldGeneration(self.objects.items[0].position);
        }

        for (self.objects.items) |*obj| {
            if (!obj.body_id.isValid()) {
                continue;
            }

            if (obj.dirty) {
                try obj.recalculatePhysics(&self.physics);
            }

            const pos = self.physics.getPosition(obj.body_id);
            const rot = self.physics.getRotation(obj.body_id);

            obj.position = pos;
            obj.rotation = rot;
        }

        if (self.objects.items.len > 0) {
            self.camera.position = self.objects.items[0].position;
        }
    }

    fn updateWorldGeneration(self: *Self, pos: Vec2) !void {
        const chunk_x = @as(i32, @intFromFloat(math.floor(pos.x / CHUNK_SIZE)));
        const chunk_y = @as(i32, @intFromFloat(math.floor(pos.y / CHUNK_SIZE)));
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
        const unload_dist = CHUNK_SIZE * 6.0;
        const unload_dist_sq = unload_dist * unload_dist;

        var i: usize = self.objects.items.len;
        while (i > 1) {
            i -= 1;
            const obj = &self.objects.items[i];

            const dx = obj.position.x - player_pos.x;
            const dy = obj.position.y - player_pos.y;
            const dist_sq = dx * dx + dy * dy;

            if (dist_sq > unload_dist_sq) {
                const chunk_x = @as(i32, @intFromFloat(math.floor(obj.position.x / CHUNK_SIZE)));
                const chunk_y = @as(i32, @intFromFloat(math.floor(obj.position.y / CHUNK_SIZE)));
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
        const chunk_world_x = @as(f32, @floatFromInt(coord.x)) * CHUNK_SIZE;
        const chunk_world_y = @as(f32, @floatFromInt(coord.y)) * CHUNK_SIZE;
        const center = Vec2.init(chunk_world_x + CHUNK_SIZE * 0.5, chunk_world_y + CHUNK_SIZE * 0.5);

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

            const jitter_x = rand.float(f32) * (CHUNK_SIZE * 0.6) + (CHUNK_SIZE * 0.2);
            const jitter_y = rand.float(f32) * (CHUNK_SIZE * 0.6) + (CHUNK_SIZE * 0.2);
            const spawn_pos = Vec2.init(chunk_world_x + jitter_x, chunk_world_y + jitter_y);

            var resources = try std.ArrayList(AsteroidGenerator.ResourceConfig).initCapacity(self.allocator, 5);
            defer resources.deinit();

            if (rules.iron_prob > 0) resources.appendAssumeCapacity(.{ .resource = .iron, .probability = rules.iron_prob, .min_amount = 2, .max_amount = 10 });
            if (rules.carbon_prob > 0) resources.appendAssumeCapacity(.{ .resource = .carbon, .probability = rules.carbon_prob, .min_amount = 2, .max_amount = 10 });
            if (rules.copper_prob > 0) resources.appendAssumeCapacity(.{ .resource = .copper, .probability = rules.copper_prob, .min_amount = 2, .max_amount = 8 });
            if (rules.gold_prob > 0) resources.appendAssumeCapacity(.{ .resource = .gold, .probability = rules.gold_prob, .min_amount = 1, .max_amount = 5 });
            if (rules.uranium_prob > 0) resources.appendAssumeCapacity(.{ .resource = .uranium, .probability = rules.uranium_prob, .min_amount = 1, .max_amount = 3 });

            var asteroid = try AsteroidGenerator.createAsteroid(
                self.allocator,
                self.generateObjectId(),
                spawn_pos,
                w,
                h,
                .irregular,
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
        }
    }

    pub fn onScroll(self: *Self, xoffset: f64, yoffset: f64) void {
        _ = xoffset;

        if (yoffset > 0) {
            self.camera.zoom *= 1.1;
        } else if (yoffset < 0) {
            self.camera.zoom *= 0.9;
        }

        self.camera.zoom = @max(0.1, @min(10.0, self.camera.zoom));
    }
};

pub fn scrollCallback(window: *zglfw.Window, xoffset: f64, yoffset: f64) callconv(.c) void {
    const world = zglfw.getWindowUserPointer(window, World) orelse return;

    world.onScroll(xoffset, yoffset);
}
