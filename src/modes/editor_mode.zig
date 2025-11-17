const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");
const zgui = @import("zgui");

pub const EditorMode = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    gctx: *zgpu.GraphicsContext,
    window: *zglfw.Window,

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        window: *zglfw.Window,
    ) !Self {
        return .{
            .allocator = allocator,
            .gctx = gctx,
            .window = window,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn update(self: *Self, dt: f32) !void {
        _ = self;
        _ = dt;
    }

    pub fn render(self: *Self, pass: zgpu.wgpu.RenderPassEncoder) !void {
        _ = self;
        _ = pass;
    }
};
