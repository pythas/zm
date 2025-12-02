const std = @import("std");

const Map = @import("map.zig").Map;
const Chunk = @import("chunk.zig").Chunk;
const Vec2 = @import("vec2.zig").Vec2;

pub const tilemapWidth = 16;
pub const tilemapHeight = 16;

pub const TileReference = struct {
    const Self = @This();

    chunk_x: i32,
    chunk_y: i32,
    tile_x: u32,
    tile_y: u32,

    pub fn worldCenter(self: Self) Vec2 {
        const tile_size: f32 = Tile.tileSize;
        const tiles_per_chunk_f: f32 = @floatFromInt(Chunk.chunkSize);
        const chunk_size_world: f32 = tile_size * tiles_per_chunk_f;

        const chunk_center_x: f32 =
            @as(f32, @floatFromInt(self.chunk_x)) * chunk_size_world;
        const chunk_center_y: f32 =
            @as(f32, @floatFromInt(self.chunk_y)) * chunk_size_world;

        const tile_x_f: f32 = @as(f32, @floatFromInt(self.tile_x));
        const tile_y_f: f32 = @as(f32, @floatFromInt(self.tile_y));

        const half_tiles = tiles_per_chunk_f / 2.0;

        const local_x_tiles = (tile_x_f + 0.5) - half_tiles;
        const local_y_tiles = (tile_y_f + 0.5) - half_tiles;

        return Vec2.init(
            chunk_center_x + local_x_tiles * tile_size,
            chunk_center_y + local_y_tiles * tile_size,
        );
    }

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
    Engine,
    RCS,
    Laser,
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

pub const Direction = enum(u8) {
    North = 0,
    East = 1,
    South = 2,
    West = 3,
};

pub const Directions: []const struct {
    direction: Direction,
    dx: i32,
    dy: i32,
} = &.{
    .{ .direction = Direction.North, .dx = 0, .dy = -1 },
    .{ .direction = Direction.South, .dx = 0, .dy = 1 },
    .{ .direction = Direction.East, .dx = 1, .dy = 0 },
    .{ .direction = Direction.West, .dx = -1, .dy = 0 },
};

pub const Offset = struct {
    dx: isize,
    dy: isize,
};

pub const Tile = struct {
    const Self = @This();
    pub const tileSize: usize = 8;

    category: Category,
    composition: Composition,
    sheet: SpriteSheet,
    sprite: u16,
    rotation: Direction = .North,

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
