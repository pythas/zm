const std = @import("std");
const UiRenderer = @import("renderer/ui_renderer.zig").UiRenderer;
const Font = @import("renderer/font.zig").Font;
const UiVec4 = @import("renderer/ui_renderer.zig").UiVec4;
const UiVec2 = @import("renderer/ui_renderer.zig").UiVec2;
const UiRect = @import("renderer/ui_renderer.zig").UiRect;

pub const NotificationType = enum {
    auto_dismiss,
    manual_dismiss,
};

pub const Notification = struct {
    const Self = @This();

    text: [64]u8,
    len: usize,
    timer: f32,
    color: UiVec4,
    type: NotificationType,
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

    pub fn add(self: *Self, text: []const u8, color: UiVec4, n_type: NotificationType) void {
        var n = Notification{
            .text = undefined,
            .len = 0,
            .timer = 3.0,
            .color = color,
            .type = n_type,
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

            if (n.type == .auto_dismiss) {
                n.timer -= dt;
                if (n.timer <= 0) {
                    _ = self.notifications.orderedRemove(i);
                    continue;
                }
            }

            i += 1;
        }
    }

    pub fn draw(self: *Self, ui: *UiRenderer, screen_w: f32, screen_h: f32, font: *const Font) !void {
        const bottom_margin: f32 = 20.0;
        const right_margin: f32 = 20.0;
        const spacing: f32 = 10.0;
        const padding: f32 = 10.0;

        var y: f32 = screen_h - bottom_margin;

        for (self.notifications.items, 0..) |n, i| {
            const text = n.text[0..n.len];

            var text_w: f32 = 0;
            for (text) |char| {
                if (font.glyphs.get(char)) |glyph| {
                    text_w += glyph.dwidth;
                }
            }

            const w = text_w + padding * 2.0;
            const h = font.line_height + padding * 2.0;

            y -= h;

            const x = screen_w - w - right_margin;
            const rect = UiRect{ .x = x, .y = y, .w = w, .h = h };

            if (n.type == .manual_dismiss) {
                const state = try ui.button(rect, false, false, text, font);
                if (state.is_clicked) {
                    _ = self.notifications.orderedRemove(i);
                    return;
                }
            } else {
                _ = try ui.panel(rect, null, null);
                try ui.label(.{ .x = x + padding, .y = y + padding + font.ascent }, text, font, n.color);
            }

            y -= spacing;
        }
    }
};
