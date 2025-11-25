const std = @import("std");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zglfw = @import("zglfw");
const shader_utils = @import("../shader_utils.zig");

const World = @import("../world.zig").World;
const Map = @import("../map.zig").Map;
const Tile = @import("../tile.zig").Tile;
const Chunk = @import("../chunk.zig").Chunk;
const Texture = @import("../texture.zig").Texture;
const Player = @import("../player.zig").Player;
const GlobalRenderState = @import("common.zig").GlobalRenderState;
const packTileForGpu = @import("common.zig").packTileForGpu;

const UiVertex = struct {
    position: UiVec2,
    uv: UiVec2,
    color: UiVec4,
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

    mouse_position: UiVec2,

    last_mouse_left_action: zglfw.Action,
    is_left_mouse_clicked: bool,

    vertices: std.ArrayList(UiVertex),

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        global: *GlobalRenderState,
    ) !Self {
        const buffer = gctx.createBuffer(.{
            .usage = .{ .copy_dst = true, .vertex = true },
            .size = 1024 * 1024, // NOTE: Not sure about this
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
            .mouse_position = .{ .x = 0, .y = 0 },
            .last_mouse_left_action = .press,
            .is_left_mouse_clicked = false,
            .vertices = vertices,
        };
    }

    pub fn beginFrame(
        self: *Self,
        mouse_position: UiVec2,
        left_mouse_action: zglfw.Action,
    ) void {
        self.vertices.clearRetainingCapacity();
        self.mouse_position = mouse_position;

        self.is_left_mouse_clicked = left_mouse_action == .release and self.last_mouse_left_action == .press;

        self.last_mouse_left_action = left_mouse_action;
    }

    fn pushQuad(self: *Self, rect: UiRect, color: UiVec4) !void {
        const x = rect.x;
        const y = rect.y;
        const w = rect.w;
        const h = rect.h;

        try self.vertices.append(.{ .position = .{ .x = x, .y = y }, .uv = .{ .x = 0, .y = 0 }, .color = color });
        try self.vertices.append(.{ .position = .{ .x = x + w, .y = y }, .uv = .{ .x = 1, .y = 0 }, .color = color });
        try self.vertices.append(.{ .position = .{ .x = x + w, .y = y + h }, .uv = .{ .x = 1, .y = 1 }, .color = color });
        try self.vertices.append(.{ .position = .{ .x = x, .y = y }, .uv = .{ .x = 0, .y = 0 }, .color = color });
        try self.vertices.append(.{ .position = .{ .x = x + w, .y = y + h }, .uv = .{ .x = 1, .y = 1 }, .color = color });
        try self.vertices.append(.{ .position = .{ .x = x, .y = y + h }, .uv = .{ .x = 0, .y = 1 }, .color = color });
    }

    pub fn panel(self: *Self, rect: UiRect) !void {
        try self.pushQuad(rect, .{ .r = 0.1, .g = 0.1, .b = 0.1, .a = 0.9 });
    }

    pub fn button(self: *Self, rect: UiRect, label_text: []const u8) !bool {
        _ = label_text;

        const is_hovered = rect.contains(self.mouse_position);
        const color = if (is_hovered)
            UiVec4{ .r = 0.25, .g = 0.25, .b = 0.35, .a = 1.0 }
        else
            UiVec4{ .r = 0.18, .g = 0.18, .b = 0.22, .a = 1.0 };

        try self.pushQuad(rect, color);

        // TODO: Add label
        // self.label(...)

        return is_hovered and self.is_left_mouse_clicked;
    }

    pub fn label(self: *Self, pos: UiVec2, text: []const u8) void {
        _ = self;
        _ = pos;
        _ = text;
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
        "vs_main",
    );
    defer vs_module.release();

    const fs_module = shader_utils.createShaderModuleWithCommon(
        gctx.device,
        @embedFile("../shaders/ui_fragment.wgsl"),
        "fs_main",
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
