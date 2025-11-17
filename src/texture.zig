const std = @import("std");
const zstbi = @import("zstbi");

pub const Texture = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    data: []u8,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) !Self {
        zstbi.init(allocator);
        defer zstbi.deinit();

        const zpath = try allocator.dupeZ(u8, path);
        defer allocator.free(zpath);

        var image = try zstbi.Image.loadFromFile(zpath, 4);
        defer image.deinit();

        std.debug.assert(image.width == 32 and image.height == 32);

        const size = image.width * image.height;
        const data = try allocator.dupe(u8, image.data[0 .. size * 4]);

        return .{
            .allocator = allocator,
            .data = data,
        };
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.data);
    }
};
