const std = @import("std");

pub const Header = struct {
    size: u32,
    bounding_box: BoundingBox,
    ascent: i32,
    descent: i32,
};

pub const BoundingBox = struct {
    w: u32,
    h: u32,
    x: i32,
    y: i32,
};

pub const Glyph = struct {
    encoding: u32,
    bounding_box: BoundingBox,
    dwidth: u32,
    bitmap: []u8,
};

pub const State = enum {
    header,
    properties,
    char_search,
    char_meta,
    bitmap,
};

pub const Bdf = struct {
    const Self = @This();

    header: Header,
    glyphs: std.AutoHashMap(u32, Glyph),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, filename: []const u8) !Self {
        var file = try std.fs.cwd().openFile(filename, .{});
        defer file.close();

        var reader = file.reader();

        var state: State = .header;

        var size: ?u32 = null;
        var bounding_box: ?BoundingBox = null;
        var ascent: ?i32 = null;
        var descent: ?i32 = null;
        var current_glyph: Glyph = undefined;

        current_glyph = std.mem.zeroes(Glyph);

        var current_bitmap_offset: usize = 0;

        var glyphs = std.AutoHashMap(u32, Glyph).init(allocator);
        errdefer {
            var it = glyphs.valueIterator();
            while (it.next()) |g| {
                allocator.free(g.bitmap);
            }
            glyphs.deinit();
        }

        var buffer: [1024]u8 = undefined;

        while (true) {
            const line_raw = reader.readUntilDelimiterOrEof(&buffer, '\n') catch |err| {
                if (err == error.StreamTooLong) return error.LineTooLong;
                return err;
            } orelse break;

            const line = std.mem.trim(u8, line_raw, " \r\t");
            if (line.len == 0) continue;

            var it = std.mem.tokenizeScalar(u8, line, ' ');
            const key = it.next() orelse continue;

            switch (state) {
                .header => {
                    if (std.mem.eql(u8, key, "SIZE")) {
                        const size_str = it.next() orelse "0";
                        size = try std.fmt.parseInt(u32, size_str, 10);
                    } else if (std.mem.eql(u8, key, "FONTBOUNDINGBOX")) {
                        const w_str = it.next() orelse "0";
                        const h_str = it.next() orelse "0";
                        const x_str = it.next() orelse "0";
                        const y_str = it.next() orelse "0";

                        bounding_box = .{
                            .w = try std.fmt.parseInt(u32, w_str, 10),
                            .h = try std.fmt.parseInt(u32, h_str, 10),
                            .x = try std.fmt.parseInt(i32, x_str, 10),
                            .y = try std.fmt.parseInt(i32, y_str, 10),
                        };
                    } else if (std.mem.eql(u8, key, "STARTPROPERTIES")) {
                        state = .properties;
                    } else if (std.mem.eql(u8, key, "CHARS")) {
                        state = .char_search;
                    }
                },
                .properties => {
                    if (std.mem.eql(u8, key, "FONT_ASCENT")) {
                        const ascent_str = it.next() orelse "";
                        ascent = try std.fmt.parseInt(i32, ascent_str, 10);
                    } else if (std.mem.eql(u8, key, "FONT_DESCENT")) {
                        const descent_str = it.next() orelse "";
                        descent = try std.fmt.parseInt(i32, descent_str, 10);
                    } else if (std.mem.eql(u8, key, "ENDPROPERTIES")) {
                        state = .header;
                    }
                },
                .char_search => {
                    if (std.mem.eql(u8, key, "STARTCHAR")) {
                        current_glyph = std.mem.zeroes(Glyph);
                        state = .char_meta;
                    }
                },
                .char_meta => {
                    if (std.mem.eql(u8, key, "ENCODING")) {
                        const enc_str = it.next() orelse "0";
                        current_glyph.encoding = try std.fmt.parseInt(u32, enc_str, 10);
                    } else if (std.mem.eql(u8, key, "DWIDTH")) {
                        const dw_str = it.next() orelse "0";
                        current_glyph.dwidth = try std.fmt.parseInt(u32, dw_str, 10);
                    } else if (std.mem.eql(u8, key, "BBX")) {
                        const w_str = it.next() orelse "0";
                        const h_str = it.next() orelse "0";
                        const x_str = it.next() orelse "0";
                        const y_str = it.next() orelse "0";

                        current_glyph.bounding_box = .{
                            .w = try std.fmt.parseInt(u32, w_str, 10),
                            .h = try std.fmt.parseInt(u32, h_str, 10),
                            .x = try std.fmt.parseInt(i32, x_str, 10),
                            .y = try std.fmt.parseInt(i32, y_str, 10),
                        };
                    } else if (std.mem.eql(u8, key, "BITMAP")) {
                        state = .bitmap;
                        const w = current_glyph.bounding_box.w;
                        const h = current_glyph.bounding_box.h;
                        const bytes_per_row = (w + 7) / 8;
                        const total_bytes = h * bytes_per_row;
                        current_glyph.bitmap = try allocator.alloc(u8, total_bytes);
                        @memset(current_glyph.bitmap, 0);
                        current_bitmap_offset = 0;
                    }
                },
                .bitmap => {
                    if (std.mem.eql(u8, key, "ENDCHAR")) {
                        try glyphs.put(current_glyph.encoding, current_glyph);
                        state = .char_search;
                    } else {
                        var i: usize = 0;
                        while (i < key.len) : (i += 2) {
                            if (i + 2 > key.len) break;
                            const byte = try std.fmt.parseInt(u8, key[i .. i + 2], 16);
                            if (current_bitmap_offset < current_glyph.bitmap.len) {
                                current_glyph.bitmap[current_bitmap_offset] = byte;
                                current_bitmap_offset += 1;
                            }
                        }
                    }
                },
            }
        }

        if (size == null or bounding_box == null) {
            return error.CouldNotParse;
        }

        return Self{
            .allocator = allocator,
            .header = .{
                .size = size.?,
                .bounding_box = bounding_box.?,
                .ascent = ascent orelse 0,
                .descent = descent orelse 0,
            },
            .glyphs = glyphs,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.glyphs.valueIterator();
        while (it.next()) |glyph| {
            self.allocator.free(glyph.bitmap);
        }
        self.glyphs.deinit();
    }
};

