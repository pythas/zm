const std = @import("std");
const UiRenderer = @import("renderer/ui_renderer.zig").UiRenderer;
const Font = @import("renderer/font.zig").Font;
const UiVec4 = @import("renderer/ui_renderer.zig").UiVec4;

pub const Notification = struct {
    const Self = @This();

    text: [64]u8,
    len: usize,
    timer: f32,
    color: UiVec4,
};

pub const NotificationSystem = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    notifications: std.ArrayList(Notification),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .notifications = std.ArrayList(Notification).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.notifications.deinit();
    }

    pub fn add(self: *Self, text: []const u8, color: UiVec4) void {
        var n = Notification{
            .text = undefined,
            .len = 0,
            .timer = 3.0,
            .color = color,
        };

        const len = @min(text.len, n.text.len);
        @memcpy(n.text[0..len], text[0..len]);
        n.len = len;

        self.notifications.append(n) catch {};
    }

    pub fn update(self: *Self, dt: f32) void {
        var i: usize = 0;
        while (i < self.notifications.items.len) {
            var n = &self.notifications.items[i];
            n.timer -= dt;

            if (n.timer <= 0) {
                _ = self.notifications.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    pub fn draw(self: *Self, ui: *UiRenderer, screen_w: f32, font: *const Font) !void {
        var y: f32 = 100.0;
        const spacing: f32 = 20.0;

        for (self.notifications.items) |n| {
            const text = n.text[0..n.len];

            var text_w: f32 = 0;
            for (text) |char| {
                if (font.glyphs.get(char)) |glyph| {
                    text_w += glyph.dwidth;
                }
            }

            const x = (screen_w - text_w) / 2.0;
            try ui.label(.{ .x = x, .y = y }, text, font, ui.style.text_color);
            y += spacing;
        }
    }
};
