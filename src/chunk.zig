const std = @import("std");
const zgpu = @import("zgpu");

const Map = @import("map.zig").Map;
const Tile = @import("tile.zig").Tile;
const TileReference = @import("tile.zig").TileReference;
const Vec2 = @import("vec2.zig").Vec2;
const tileSize = @import("tile.zig").tileSize;

pub const chunkSize = 64;
pub const chunkPixelSize = chunkSize * tileSize;

pub const ChunkReference = struct {
    const Self = @This();

    chunk_x: i32,
    chunk_y: i32,

    pub fn getChunk(self: Self, map: *Map) ?*Chunk {
        for (map.chunks.items) |*chunk| {
            if (chunk.x == self.chunk_x and chunk.y == self.chunk_y) {
                return chunk;
            }
        }

        return null;
    }
};

pub const Chunk = struct {
    const Self = @This();

    pub const RenderData = struct {
        tilemap: zgpu.TextureHandle,
        tilemap_view: zgpu.TextureViewHandle,
        uniform_buffer: zgpu.BufferHandle,
        bind_group: zgpu.BindGroupHandle,
    };

    x: i32,
    y: i32,
    tiles: [chunkSize][chunkSize]Tile,
    render_data: ?RenderData = null,

    pub fn initEmpty(allocator: std.mem.Allocator, x: i32, y: i32) !Self {
        const tiles: [chunkSize][chunkSize]Tile =
            .{.{try Tile.initEmpty(allocator)} ** chunkSize} ** chunkSize;

        return .{
            .x = x,
            .y = y,
            .tiles = tiles,
        };
    }

    pub fn initTest(allocator: std.mem.Allocator, x: i32, y: i32) !Self {
        var tiles: [64][64]Tile = undefined;

        for (0..chunkSize) |chunk_x| {
            for (0..chunkSize) |chunk_y| {
                tiles[chunk_x][chunk_y] = try Tile.initEmpty(allocator);
            }
        }

        tiles[31][0] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);

        // tiles[0][0] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        // tiles[63][0] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        // tiles[63][63] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        // tiles[0][63] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);

        // tiles[51][50] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        // tiles[52][50] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        // tiles[53][50] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        // tiles[50][51] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        // tiles[51][51] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        // tiles[52][51] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        // tiles[53][51] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        // tiles[54][51] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        // tiles[50][52] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        // var tile = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 1);
        // try tile.composition.setOre(.Iron, 255);
        // tiles[51][52] = tile;
        // tiles[52][52] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        // tiles[53][52] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        // tiles[54][52] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        // tiles[50][53] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        // tiles[51][53] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        // tiles[52][53] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        // tiles[53][53] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        // tiles[54][53] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        // tiles[51][54] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        // tiles[52][54] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        // tiles[53][54] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);

        return .{
            .x = x,
            .y = y,
            .tiles = tiles,
        };
    }

    pub fn worldCenter(self: Chunk) Vec2 {
        return .{
            .x = @as(f32, @floatFromInt(self.x)) * chunkPixelSize,
            .y = @as(f32, @floatFromInt(self.y)) * chunkPixelSize,
        };
    }

    pub fn containsWorld(self: Self, world: Vec2) bool {
        const half = chunkPixelSize / 2.0;
        const center = self.worldCenter();
        const left = center.x - half;
        const right = center.x + half;
        const top = center.y - half;
        const bottom = center.y + half;

        return world.x >= left and world.x < right and
            world.y >= top and world.y < bottom;
    }

    pub fn tileAtWorld(self: *Self, world: Vec2) ?TileReference {
        const half = chunkPixelSize / 2.0;
        const center = self.worldCenter();
        const left = center.x - half;
        const top = center.y - half;

        const rel_x = world.x - left;
        const rel_y = world.y - top;

        const tile_x: u32 = @intFromFloat(rel_x / tileSize);
        const tile_y: u32 = @intFromFloat(rel_y / tileSize);

        if (tile_x >= chunkSize or tile_y >= chunkSize) {
            return null;
        }

        return .{
            .chunk_x = self.x,
            .chunk_y = self.y,
            .tile_x = tile_x,
            .tile_y = tile_y,
        };
    }
};
