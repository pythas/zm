const std = @import("std");
const znoise = @import("znoise");
const Vec2 = @import("vec2.zig").Vec2;
const Resource = @import("resource.zig").Resource;

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
    noise: znoise.FnlGenerator,

    pub fn init(seed: i32) WorldGenerator {
        const noise = znoise.FnlGenerator{
            .seed = seed,
            .noise_type = .opensimplex2,
            .frequency = 0.01,
        };
        return .{ .noise = noise };
    }

    pub fn shouldSpawnAsteroid(self: WorldGenerator, chunk_x: i32, chunk_y: i32, density: f32) bool {
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
};
