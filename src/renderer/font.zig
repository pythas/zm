const std = @import("std");
const Bdf = @import("../bdf.zig").Bdf;

pub const FontGlyph = struct {
    uv_rect: [4]f32,
    width: f32,
    height: f32,
    offset_x: f32,
    offset_y: f32,
    dwidth: f32,
};

pub const Font = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    glyphs: std.AutoHashMap(u32, FontGlyph),
    texture_data: []u8,
    ascent: f32,
    descent: f32,
    line_height: f32,

    pub fn init(allocator: std.mem.Allocator, bdf_path: []const u8) !Self {
        var bdf = try Bdf.init(allocator, bdf_path);
        defer bdf.deinit();

        const tex_w = 256;
        const tex_h = 256;
        const texture_data = try allocator.alloc(u8, tex_w * tex_h * 4);
        @memset(texture_data, 0);

        var glyphs = std.AutoHashMap(u32, FontGlyph).init(allocator);

        var x: u32 = 0;
        var y: u32 = 0;
        const padding = 1;

        var max_h: u32 = 0;

        var it = bdf.glyphs.iterator();
        while (it.next()) |entry| {
            const char_code = entry.key_ptr.*;
            const glyph = entry.value_ptr.*;

            const gw = glyph.bounding_box.w;
            const gh = glyph.bounding_box.h;

            if (x + gw + padding > tex_w) {
                x = 0;
                y += max_h + padding;
                max_h = 0;
            }

            if (y + gh > tex_h) {
                std.debug.print("Font texture overflow!\n", .{});
                break;
            }

            if (gh > max_h) max_h = gh;

            const bytes_per_row = (gw + 7) / 8;

            for (0..gh) |row| {
                for (0..gw) |col| {
                    const byte_idx = row * bytes_per_row + (col / 8);
                    const bit_idx = 7 - (col % 8);
                    const byte = glyph.bitmap[byte_idx];
                    const pixel = (byte >> @intCast(bit_idx)) & 1;

                    if (pixel == 1) {
                        const tx = x + col;
                        const ty = y + row;
                        const idx = (ty * tex_w + tx) * 4;
                        texture_data[idx + 0] = 255;
                        texture_data[idx + 1] = 255;
                        texture_data[idx + 2] = 255;
                        texture_data[idx + 3] = 255;
                    }
                }
            }

            try glyphs.put(char_code, .{
                .uv_rect = .{
                    @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(tex_w)),
                    @as(f32, @floatFromInt(y)) / @as(f32, @floatFromInt(tex_h)),
                    @as(f32, @floatFromInt(gw)) / @as(f32, @floatFromInt(tex_w)),
                    @as(f32, @floatFromInt(gh)) / @as(f32, @floatFromInt(tex_h)),
                },
                .width = @floatFromInt(gw),
                .height = @floatFromInt(gh),
                .offset_x = @floatFromInt(glyph.bounding_box.x),
                .offset_y = @floatFromInt(glyph.bounding_box.y),
                .dwidth = @floatFromInt(glyph.dwidth),
            });

            x += gw + padding;
        }

        return .{
            .allocator = allocator,
            .glyphs = glyphs,
            .texture_data = texture_data,
            .ascent = @floatFromInt(bdf.header.ascent),
            .descent = @floatFromInt(bdf.header.descent),
            .line_height = @floatFromInt(bdf.header.ascent + bdf.header.descent),
        };
    }

    pub fn deinit(self: *Self) void {
        self.glyphs.deinit();
        self.allocator.free(self.texture_data);
    }
};
