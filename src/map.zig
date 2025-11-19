const std = @import("std");
const zstbi = @import("zstbi");
const zgpu = @import("zgpu");

const Tile = @import("tile.zig").Tile;

pub const Chunk = struct {
    const Self = @This();
    pub const chunkSize: usize = 64;

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

        tiles[0][0] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        tiles[63][0] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        tiles[63][63] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);
        tiles[0][63] = try Tile.init(allocator, .Terrain, .Rock, .Asteroids, 0);

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
};

pub const Map = struct {
    const Self = @This();

    chunks: std.ArrayList(Chunk),

    pub fn init(allocator: std.mem.Allocator) !Self {
        var chunks = std.ArrayList(Chunk).init(allocator);

        // try chunks.append(try Chunk.initEmpty(allocator, -1, -1));
        // try chunks.append(try Chunk.initEmpty(allocator, 0, -1));
        // try chunks.append(try Chunk.initEmpty(allocator, 1, -1));
        // try chunks.append(try Chunk.initEmpty(allocator, -1, 0));
        // try chunks.append(try Chunk.initTest(allocator, 0, 0));
        // try chunks.append(try Chunk.initEmpty(allocator, 1, 0));
        // try chunks.append(try Chunk.initEmpty(allocator, -1, 1));
        // try chunks.append(try Chunk.initEmpty(allocator, 0, 1));
        // try chunks.append(try Chunk.initEmpty(allocator, 1, 1));

        try chunks.append(try Chunk.initTest(allocator, -1, -1));
        try chunks.append(try Chunk.initTest(allocator, 0, -1));
        try chunks.append(try Chunk.initTest(allocator, 1, -1));
        try chunks.append(try Chunk.initTest(allocator, -1, 0));
        try chunks.append(try Chunk.initTest(allocator, 0, 0));
        try chunks.append(try Chunk.initTest(allocator, 1, 0));
        try chunks.append(try Chunk.initTest(allocator, -1, 1));
        try chunks.append(try Chunk.initTest(allocator, 0, 1));
        try chunks.append(try Chunk.initTest(allocator, 1, 1));

        return .{
            .chunks = chunks,
        };
    }

    pub fn deinit(self: Self) void {
        self.chunks.deinit();
    }

    pub fn getTile(self: Self, x: i32, y: i32) ?Tile {
        if (x < 0 or y < 0 or x >= self.width or y >= self.height) {
            return null;
        }

        return self.data[@as(usize, @intCast(y)) * self.width + @as(usize, @intCast(x))];
    }
};
