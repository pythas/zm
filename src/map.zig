const std = @import("std");
const zstbi = @import("zstbi");
const zgpu = @import("zgpu");

pub const Tile = struct {
    const Self = @This();

    pub const Kind = enum(u8) {
        Empty = 0,
        Stone = 1,
    };

    kind: Kind,
    texture: u8,

    pub fn init(kind: Kind, texture: u8) Self {
        return .{
            .kind = kind,
            .texture = texture,
        };
    }

    pub fn initEmpty() Self {
        return .{
            .kind = .Empty,
            .texture = 0,
        };
    }
};

pub const Chunk = struct {
    const Self = @This();
    pub const chunkWidth: usize = 64;
    pub const chunkHeight: usize = 64;

    pub const RenderData = struct {
        tilemap: zgpu.TextureHandle,
        tilemap_view: zgpu.TextureViewHandle,
        uniform_buffer: zgpu.BufferHandle,
        bind_group: zgpu.BindGroupHandle,
    };

    x: i32,
    y: i32,
    tiles: [chunkWidth][chunkHeight]Tile,
    render_data: ?RenderData = null,

    pub fn initEmpty(x: i32, y: i32) Self {
        const tiles: [chunkWidth][chunkHeight]Tile =
            .{.{Tile.initEmpty()} ** chunkHeight} ** chunkWidth;

        return .{
            .x = x,
            .y = y,
            .tiles = tiles,
        };
    }

    pub fn initTest(x: i32, y: i32) Self {
        var tiles: [64][64]Tile = undefined;

        for (0..chunkWidth) |chunk_x| {
            for (0..chunkHeight) |chunk_y| {
                tiles[chunk_x][chunk_y] = Tile.initEmpty();
            }
        }

        // tiles[0][0] = Tile.init(.Stone, 0);
        // tiles[63][0] = Tile.init(.Stone, 0);
        // tiles[63][63] = Tile.init(.Stone, 0);
        // tiles[0][63] = Tile.init(.Stone, 0);

        tiles[51][50] = Tile.init(.Stone, 0);
        tiles[52][50] = Tile.init(.Stone, 0);
        tiles[53][50] = Tile.init(.Stone, 0);
        tiles[50][51] = Tile.init(.Stone, 0);
        tiles[51][51] = Tile.init(.Stone, 0);
        tiles[52][51] = Tile.init(.Stone, 0);
        tiles[53][51] = Tile.init(.Stone, 0);
        tiles[54][51] = Tile.init(.Stone, 0);
        tiles[50][52] = Tile.init(.Stone, 0);
        tiles[51][52] = Tile.init(.Stone, 0);
        tiles[52][52] = Tile.init(.Stone, 0);
        tiles[53][52] = Tile.init(.Stone, 0);
        tiles[54][52] = Tile.init(.Stone, 0);
        tiles[50][53] = Tile.init(.Stone, 0);
        tiles[51][53] = Tile.init(.Stone, 0);
        tiles[52][53] = Tile.init(.Stone, 0);
        tiles[53][53] = Tile.init(.Stone, 0);
        tiles[54][53] = Tile.init(.Stone, 0);
        tiles[51][54] = Tile.init(.Stone, 0);
        tiles[52][54] = Tile.init(.Stone, 0);
        tiles[53][54] = Tile.init(.Stone, 0);

        return .{
            .x = x,
            .y = y,
            .tiles = tiles,
        };
    }
};

pub const Map = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    chunks: std.ArrayList(Chunk),

    pub fn init(allocator: std.mem.Allocator) !Self {
        var chunks = std.ArrayList(Chunk).init(allocator);

        try chunks.append(Chunk.initTest(-1, -1));
        try chunks.append(Chunk.initTest(0, -1));
        try chunks.append(Chunk.initTest(1, -1));

        try chunks.append(Chunk.initTest(-1, 0));
        try chunks.append(Chunk.initTest(0, 0));
        try chunks.append(Chunk.initTest(1, 0));

        try chunks.append(Chunk.initTest(-1, 1));
        try chunks.append(Chunk.initTest(0, 1));
        try chunks.append(Chunk.initTest(1, 1));

        return .{
            .allocator = allocator,
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
