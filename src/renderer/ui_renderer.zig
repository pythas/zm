const std = @import("std");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zglfw = @import("zglfw");
const shader_utils = @import("../shader_utils.zig");

const MouseState = @import("../input.zig").MouseState;
const World = @import("../world.zig").World;
const Tile = @import("../tile.zig").Tile;
const Sprite = @import("../tile.zig").Sprite;
const Texture = @import("../texture.zig").Texture;
const Assets = @import("../assets.zig").Assets;
const GlobalRenderState = @import("common.zig").GlobalRenderState;
const packTileForGpu = @import("common.zig").packTileForGpu;
const packSpriteForGpu = @import("common.zig").packSpriteForGpu;
const Item = @import("../inventory.zig").Item;

const UiVertex = struct {
    position: UiVec2,
    uv: UiVec2,
    color: UiVec4,
    data: u32,
    mode: u32,
};

pub const UiVec2 = struct {
    x: f32,
    y: f32,
};

pub const UiVec4 = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

pub const UiRect = struct {
    const Self = @This();

    x: f32,
    y: f32,
    w: f32,
    h: f32,

    pub fn contains(self: Self, position: UiVec2) bool {
        return position.x >= self.x and position.x <= self.x + self.w and
            position.y >= self.y and position.y <= self.y + self.h;
    }
};

pub const UiRenderer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    gctx: *zgpu.GraphicsContext,
    pipeline_layout: zgpu.PipelineLayoutHandle,
    pipeline: zgpu.RenderPipelineHandle,
    buffer: zgpu.BufferHandle,
    vertices: std.ArrayList(UiVertex),

    mouse: MouseState,

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        window: *zglfw.Window,
        global: *GlobalRenderState,
    ) !Self {
        const buffer = gctx.createBuffer(.{
            .usage = .{ .copy_dst = true, .vertex = true },
            .size = 1024 * 1024,
        });

        const pipeline_layout = gctx.createPipelineLayout(&.{
            global.layout,
        });

        const pipeline = try createPipeline(
            gctx,
            pipeline_layout,
        );

        const vertices = std.ArrayList(UiVertex).init(allocator);

        return .{
            .allocator = allocator,
            .gctx = gctx,
            .pipeline_layout = pipeline_layout,
            .pipeline = pipeline,
            .buffer = buffer,
            .vertices = vertices,
            .mouse = MouseState.init(window),
        };
    }

    pub fn deinit(self: *Self) void {
        self.vertices.deinit();
    }

    pub fn beginFrame(
        self: *Self,
    ) void {
        self.vertices.clearRetainingCapacity();
        self.mouse.update();
    }

    fn pushQuad(self: *Self, rect: UiRect, color: UiVec4, data: u32, mode: u32) !void {
        const x = rect.x;
        const y = rect.y;
        const w = rect.w;
        const h = rect.h;

        try self.vertices.append(.{ .position = .{ .x = x, .y = y }, .uv = .{ .x = 0, .y = 0 }, .color = color, .data = data, .mode = mode });
        try self.vertices.append(.{ .position = .{ .x = x + w, .y = y }, .uv = .{ .x = 1, .y = 0 }, .color = color, .data = data, .mode = mode });
        try self.vertices.append(.{ .position = .{ .x = x + w, .y = y + h }, .uv = .{ .x = 1, .y = 1 }, .color = color, .data = data, .mode = mode });
        try self.vertices.append(.{ .position = .{ .x = x, .y = y }, .uv = .{ .x = 0, .y = 0 }, .color = color, .data = data, .mode = mode });
        try self.vertices.append(.{ .position = .{ .x = x + w, .y = y + h }, .uv = .{ .x = 1, .y = 1 }, .color = color, .data = data, .mode = mode });
        try self.vertices.append(.{ .position = .{ .x = x, .y = y + h }, .uv = .{ .x = 0, .y = 1 }, .color = color, .data = data, .mode = mode });
    }

    pub fn panel(self: *Self, rect: UiRect) !void {
        try self.pushQuad(rect, .{ .r = 0.1, .g = 0.1, .b = 0.1, .a = 0.9 }, 0, 0);
    }

    pub fn sprite(self: *Self, rect: UiRect, s: Sprite) !void {
        const data = packSpriteForGpu(s);

        try self.pushQuad(rect, .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 }, data, 1);
    }

    pub fn inventorySlot(self: *Self, rect: UiRect, item: Item, is_selected: bool) !bool {
        const is_hovered = rect.contains(UiVec2{ .x = self.mouse.x, .y = self.mouse.y });

        var color = if (is_selected)
            UiVec4{ .r = 0.3, .g = 0.3, .b = 0.4, .a = 1.0 }
        else
            UiVec4{ .r = 0.15, .g = 0.15, .b = 0.15, .a = 1.0 };

        color = if (is_hovered)
            UiVec4{ .r = 0.4, .g = 0.4, .b = 0.5, .a = 1.0 }
        else
            color;

        try self.pushQuad(rect, color, 0, 0);

        switch (item) {
            .none => {},
            .resource => |r| {
                const s = Assets.getResourceSprite(r);
                const inset: f32 = 4.0;
                const sprite_rect = UiRect{
                    .x = rect.x + inset,
                    .y = rect.y + inset,
                    .w = rect.w - inset * 2.0,
                    .h = rect.h - inset * 2.0,
                };
                try self.sprite(sprite_rect, s);
            },
            .tool => |t| {
                const s = Assets.getToolSprite(t);
                const inset: f32 = 4.0;
                const sprite_rect = UiRect{
                    .x = rect.x + inset,
                    .y = rect.y + inset,
                    .w = rect.w - inset * 2.0,
                    .h = rect.h - inset * 2.0,
                };
                try self.sprite(sprite_rect, s);
            },
        }

        return is_hovered and self.mouse.is_left_clicked;
    }

    pub fn toolSlot(self: *Self, rect: UiRect, item: Item, is_selected: bool) !bool {
        const is_hovered = rect.contains(UiVec2{ .x = self.mouse.x, .y = self.mouse.y });

        var color = if (is_selected)
            UiVec4{ .r = 0.3, .g = 0.3, .b = 0.4, .a = 1.0 }
        else
            UiVec4{ .r = 0.15, .g = 0.15, .b = 0.15, .a = 1.0 };

        color = if (is_hovered)
            UiVec4{ .r = 0.4, .g = 0.4, .b = 0.5, .a = 1.0 }
        else
            color;

        try self.pushQuad(rect, color, 0, 0);

        switch (item) {
            .none => {},
            .resource => {},
            .tool => |t| {
                const s = Assets.getToolSprite(t);
                const inset: f32 = 4.0;
                const sprite_rect = UiRect{
                    .x = rect.x + inset,
                    .y = rect.y + inset,
                    .w = rect.w - inset * 2.0,
                    .h = rect.h - inset * 2.0,
                };
                try self.sprite(sprite_rect, s);
            },
        }

        return is_hovered and self.mouse.is_left_clicked;
    }

    pub fn button(self: *Self, rect: UiRect, is_active: bool, label_text: []const u8) !bool {
        _ = label_text;

        const is_hovered = rect.contains(UiVec2{ .x = self.mouse.x, .y = self.mouse.y });
        var color = if (is_active)
            UiVec4{ .r = 0.25, .g = 0.25, .b = 0.35, .a = 1.0 }
        else
            UiVec4{ .r = 0.18, .g = 0.18, .b = 0.22, .a = 1.0 };

        color = if (is_hovered)
            UiVec4{ .r = 0.35, .g = 0.35, .b = 0.45, .a = 1.0 }
        else
            color;

        try self.pushQuad(rect, color, 0, 0);

        // TODO: Add label
        // self.label(...)

        return is_hovered and self.mouse.is_left_clicked;
    }

    pub fn label(self: *Self, pos: UiVec2, text: []const u8) void {
        _ = self;
        _ = pos;
        _ = text;
        // TODO: ...
    }

    pub fn endFrame(
        self: Self,
        pass: zgpu.wgpu.RenderPassEncoder,
        global: *const GlobalRenderState,
    ) void {
        if (self.vertices.items.len == 0) {
            return;
        }

        const slice = std.mem.sliceAsBytes(self.vertices.items);
        self.gctx.queue.writeBuffer(
            self.gctx.lookupResource(self.buffer).?,
            0,
            u8,
            slice,
        );

        const pipeline = self.gctx.lookupResource(self.pipeline).?;
        const global_bind_group = self.gctx.lookupResource(global.bind_group).?;
        const buffer = self.gctx.lookupResource(self.buffer).?;

        const count: u32 = @intCast(self.vertices.items.len);

        pass.setPipeline(pipeline);
        pass.setBindGroup(0, global_bind_group, null);
        pass.setVertexBuffer(0, buffer, 0, @sizeOf(UiVertex) * count);
        pass.draw(count, 1, 0, 0);
    }
};

fn createPipeline(
    gctx: *zgpu.GraphicsContext,
    pipeline_layout: zgpu.PipelineLayoutHandle,
) !zgpu.RenderPipelineHandle {
    const vs_module = shader_utils.createShaderModuleWithCommon(
        gctx.device,
        @embedFile("../shaders/ui_vertex.wgsl"),
        "main",
    );
    defer vs_module.release();

    const fs_module = shader_utils.createShaderModuleWithCommon(
        gctx.device,
        @embedFile("../shaders/ui_fragment.wgsl"),
        "main",
    );
    defer fs_module.release();

    const color_targets = [_]wgpu.ColorTargetState{
        .{
            .format = gctx.swapchain_descriptor.format,
            .blend = &wgpu.BlendState{
                .color = .{
                    .src_factor = .src_alpha,
                    .dst_factor = .one_minus_src_alpha,
                    .operation = .add,
                },
                .alpha = .{
                    .src_factor = .one,
                    .dst_factor = .one_minus_src_alpha,
                    .operation = .add,
                },
            },
            .write_mask = .all,
        },
    };

    const vertex_attrs = [_]wgpu.VertexAttribute{
        .{
            .format = .float32x2,
            .offset = @offsetOf(UiVertex, "position"),
            .shader_location = 0,
        },

        .{
            .format = .float32x2,
            .offset = @offsetOf(UiVertex, "uv"),
            .shader_location = 1,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(UiVertex, "color"),
            .shader_location = 2,
        },
        .{
            .format = .uint32,
            .offset = @offsetOf(UiVertex, "data"),
            .shader_location = 3,
        },
        .{
            .format = .uint32,
            .offset = @offsetOf(UiVertex, "mode"),
            .shader_location = 4,
        },
    };

    const vertex_buffers = [_]wgpu.VertexBufferLayout{
        .{
            .array_stride = @sizeOf(UiVertex),
            .step_mode = .vertex,
            .attribute_count = vertex_attrs.len,
            .attributes = &vertex_attrs,
        },
    };

    const pipeline_descriptor = wgpu.RenderPipelineDescriptor{
        .vertex = .{
            .module = vs_module,
            .entry_point = "main",
            .buffer_count = vertex_buffers.len,
            .buffers = &vertex_buffers,
        },
        .primitive = .{
            .topology = .triangle_list,
            .front_face = .ccw,
            .cull_mode = .none,
        },
        .fragment = &wgpu.FragmentState{
            .module = fs_module,
            .entry_point = "main",
            .target_count = color_targets.len,
            .targets = &color_targets,
        },
    };

    return gctx.createRenderPipeline(pipeline_layout, pipeline_descriptor);
}
