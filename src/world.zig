const std = @import("std");
const math = std.math;
const zglfw = @import("zglfw");

const Physics = @import("box2d_physics.zig").Physics;
const InputManager = @import("input/input_manager.zig").InputManager;
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
const InventoryLogic = @import("systems/inventory_logic.zig").InventoryLogic;
const PhysicsLogic = @import("systems/physics_logic.zig").PhysicsLogic;
const AsteroidGenerator = @import("asteroid_generator.zig").AsteroidGenerator;
const Resource = @import("resource.zig").Resource;
const WorldGen = @import("world_gen.zig");
const WorldGenerator = WorldGen.WorldGenerator;
const ChunkCoord = WorldGen.ChunkCoord;
const rng = @import("rng.zig");
const RailgunTrail = @import("effects.zig").RailgunTrail;
const LaserBeam = @import("effects.zig").LaserBeam;
const AiController = @import("ai_controller.zig").AiController;
const config = @import("config.zig");

pub const World = struct {
    const Self = @This();

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

    pub fn init(allocator: std.mem.Allocator) !Self {
        var physics = try Physics.init(allocator);

        const camera = Camera.init(
            Vec2.init(0, 0),
        );

        const player_controller = PlayerController.init(allocator, 0);
        const ai_controller = AiController.init(allocator);
        const notifications = NotificationSystem.init(allocator);
        const world_generator = WorldGenerator.init(allocator, 12345); // TODO: load from settings

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
        };

        const ship_id = self.generateObjectId();
        var ship = ship_serialization.loadShip(allocator, ship_id, config.assets.ship_json) catch |err| switch (err) {
            error.FileNotFound => try TileObject.init(allocator, ship_id, 16, 16, Vec2.init(0, 0), 0),
            else => return err,
        };

        ship.object_type = .ship_part;

        try PhysicsLogic.recalculatePhysics(&ship, &physics);
        try InventoryLogic.initInventories(&ship);
        try self.objects.append(ship);

        // tmp: spawn a test drone nearby
        // try self.spawnEnemyDrone(Vec2.init(0, -100));

        try self.world_generator.update(&self, Vec2.init(0, 0));

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
        self.world_generator.deinit();
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
        input: *const InputManager,
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
            input,
        );

        if (self.objects.items.len > 0) {
            try self.world_generator.update(self, self.objects.items[0].position);
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

                try PhysicsLogic.recalculatePhysics(obj, &self.physics);
            }

            const pos = self.physics.getPosition(obj.body_id);
            const rot = self.physics.getRotation(obj.body_id);

            obj.position = pos;
            obj.rotation = rot;
        }

        for (new_objects_list.items) |*new_obj| {
            try PhysicsLogic.recalculatePhysics(new_obj, &self.physics);
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

    pub fn onScroll(self: *Self, xoffset: f64, yoffset: f64) void {
        _ = xoffset;

        if (yoffset > 0) {
            self.camera.zoom *= 1.1;
        } else if (yoffset < 0) {
            self.camera.zoom *= 0.9;
        }

        self.camera.zoom = @max(0.2, @min(10.0, self.camera.zoom));
    }
};

pub fn scrollCallback(window: *zglfw.Window, xoffset: f64, yoffset: f64) callconv(.c) void {
    const world = zglfw.getWindowUserPointer(window, World) orelse return;

    world.onScroll(xoffset, yoffset);
}