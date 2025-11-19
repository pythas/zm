const std = @import("std");
const zstbi = @import("zstbi");
const zgpu = @import("zgpu");

const Tile = @import("tile.zig").Tile;
const Vec2 = @import("vec2.zig").Vec2;
const Chunk = @import("chunk.zig").Chunk;

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

    pub fn getTileAtWorld(self: *Self, world: Vec2, tile_size: f32) ?Tile {
        const chunk_size = @as(f32, @floatFromInt(Chunk.chunkSize)) * tile_size;

        for (self.chunks.items) |chunk| {
            if (chunk.containsWorld(world, chunk_size)) {
                return chunk.tileAtWorld(world, tile_size, chunk_size);
            }
        }

        return null;
    }
};
