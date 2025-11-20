const std = @import("std");

const Map = @import("map.zig").Map;
const Chunk = @import("chunk.zig").Chunk;

pub const TileReference = struct {
    const Self = @This();

    chunk_x: i32,
    chunk_y: i32,
    tile_x: u32,
    tile_y: u32,

    pub fn getChunk(self: Self, map: *Map) ?*Chunk {
        for (map.chunks.items) |*chunk| {
            if (chunk.x == self.chunk_x and chunk.y == self.chunk_y) {
                return chunk;
            }
        }

        return null;
    }

    pub fn getTile(self: Self, map: *Map) ?*Tile {
        const chunk = self.getChunk(map) orelse return null;

        if (self.tile_x >= Chunk.chunkSize or self.tile_y >= Chunk.chunkSize) {
            return null;
        }

        return &chunk.tiles[self.tile_x][self.tile_y];
    }

    pub fn mineTile(self: Self, map: *Map) !void {
        const chunk = self.getChunk(map) orelse return;

        if (self.tile_x >= Chunk.chunkSize or self.tile_y >= Chunk.chunkSize) {
            return;
        }

        chunk.tiles[self.tile_x][self.tile_y] = try Tile.initEmpty(map.allocator);
        map.is_dirty = true;
    }
};

pub const Category = enum(u8) {
    Empty,
    Terrain,
    Hull,
};

pub const BaseMaterial = enum(u8) {
    Vacuum,
    Rock,
    Regolith,
    Ice,
    Metal,
    Wood,
    Composite,
    Organic,
};

pub const Ore = enum(u8) {
    Iron,
    Nickel,
    Cobalt,
    Copper,
    Gold,
    Platinum,
    Water,
    Carbon,
    Silicon,
    RareEarths,
};

pub const OreAmount = struct {
    ore: Ore,
    richness: u8,
};

pub const Composition = struct {
    const Self = @This();

    base: BaseMaterial,
    ores: std.ArrayList(OreAmount),

    pub fn init(
        allocator: std.mem.Allocator,
        base: BaseMaterial,
    ) !Self {
        return .{
            .base = base,
            .ores = std.ArrayList(OreAmount).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.ores.deinit();
    }

    pub fn setOre(self: *Self, ore: Ore, richness: u8) !void {
        for (self.ores.items) |*slot| {
            if (slot.ore == ore) {
                slot.richness = richness;
                return;
            }
        }
        try self.ores.append(.{ .ore = ore, .richness = richness });
    }
};

pub const SpriteSheet = enum(u8) {
    World = 0,
    Asteroids = 1,
    Ships = 2,
};

pub const Tile = struct {
    const Self = @This();
    pub const tileSize: usize = 8;

    category: Category,
    composition: Composition,
    sheet: SpriteSheet,
    sprite: u16,

    pub fn init(
        allocator: std.mem.Allocator,
        category: Category,
        base: BaseMaterial,
        sheet: SpriteSheet,
        sprite: u16,
    ) !Self {
        return .{
            .category = category,
            .composition = try Composition.init(allocator, base),
            .sheet = sheet,
            .sprite = sprite,
        };
    }

    pub fn initEmpty(allocator: std.mem.Allocator) !Self {
        return .{
            .category = .Empty,
            .composition = try Composition.init(allocator, .Vacuum),
            .sheet = .World,
            .sprite = 0,
        };
    }
};
