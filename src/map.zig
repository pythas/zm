const std = @import("std");
const zstbi = @import("zstbi");
const zgpu = @import("zgpu");

const Tile = @import("tile.zig").Tile;
const TileReference = @import("tile.zig").TileReference;
const ChunkReference = @import("chunk.zig").ChunkReference;
const Vec2 = @import("vec2.zig").Vec2;
const Chunk = @import("chunk.zig").Chunk;

pub const Map = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    chunks: std.ArrayList(Chunk),
    is_dirty: bool = false,

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
            .allocator = allocator,
            .chunks = chunks,
        };
    }

    pub fn deinit(self: Self) void {
        self.chunks.deinit();
    }

    pub fn getTileAtWorld(self: *Self, world: Vec2) ?TileReference {
        for (self.chunks.items) |*chunk| {
            if (chunk.containsWorld(world)) {
                return chunk.tileAtWorld(world);
            }
        }

        return null;
    }

    pub fn getChunkAtWorld(self: *Self, world: Vec2) ?ChunkReference {
        for (self.chunks.items) |*chunk| {
            if (chunk.containsWorld(world)) {
                return .{
                    .chunk_x = chunk.x,
                    .chunk_y = chunk.y,
                };
            }
        }

        return null;
    }
};
