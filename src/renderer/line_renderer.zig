const std = @import("std");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const shader_utils = @import("../shader_utils.zig");
const GlobalRenderState = @import("common.zig").GlobalRenderState;

pub const LineRenderData = extern struct {
    start: [2]f32,    // 0
    end: [2]f32,      // 8
    color: [4]f32,    // 16
    thickness: f32,   // 32
    dash_scale: f32,  // 36
    _pad: [2]f32 = .{ 0, 0 }, // 40. Align to something? size 48.
};

pub const LineRenderer = struct {
    const Self = @This();
    const maxInstances = 256;

    allocator: std.mem.Allocator,
    gctx: *zgpu.GraphicsContext,
    pipeline: zgpu.RenderPipelineHandle,
    buffer: zgpu.BufferHandle,

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        global: *GlobalRenderState,
    ) !Self {
        const instance_buffer = gctx.createBuffer(.{
            .usage = .{ .copy_dst = true, .vertex = true },
            .size = @sizeOf(LineRenderData) * maxInstances,
        });

        const pipeline_layout = gctx.createPipelineLayout(&.{
            global.layout,
        });

        const vs_module = shader_utils.createShaderModuleWithCommon(
            gctx.device,
            @embedFile("../shaders/line_vertex.wgsl"),
            "vs_main",
        );
        defer vs_module.release();

        const fs_module = shader_utils.createShaderModuleWithCommon(
            gctx.device,
            @embedFile("../shaders/line_fragment.wgsl"),
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
            .{ .format = .float32x2, .offset = @offsetOf(LineRenderData, "start"), .shader_location = 0 },
            .{ .format = .float32x2, .offset = @offsetOf(LineRenderData, "end"), .shader_location = 1 },
            .{ .format = .float32x4, .offset = @offsetOf(LineRenderData, "color"), .shader_location = 2 },
            .{ .format = .float32, .offset = @offsetOf(LineRenderData, "thickness"), .shader_location = 3 },
            .{ .format = .float32, .offset = @offsetOf(LineRenderData, "dash_scale"), .shader_location = 4 },
        };

        const vertex_buffers = [_]wgpu.VertexBufferLayout{
            .{
                .array_stride = @sizeOf(LineRenderData),
                .step_mode = .instance,
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

        const pipeline = gctx.createRenderPipeline(pipeline_layout, pipeline_descriptor);

        return .{
            .allocator = allocator,
            .gctx = gctx,
            .pipeline = pipeline,
            .buffer = instance_buffer,
        };
    }

    pub fn deinit(self: Self) void {
        _ = self;
    }

    pub fn draw(
        self: Self,
        pass: zgpu.wgpu.RenderPassEncoder,
        global: *const GlobalRenderState,
        instances: []const LineRenderData,
    ) void {
        if (instances.len == 0) return;

        const count = @min(instances.len, maxInstances);
        self.gctx.queue.writeBuffer(
            self.gctx.lookupResource(self.buffer).?,
            0,
            u8,
            std.mem.sliceAsBytes(instances[0..count]),
        );

        const pipeline = self.gctx.lookupResource(self.pipeline).?;
        const global_bind_group = self.gctx.lookupResource(global.bind_group).?;
        const buffer = self.gctx.lookupResource(self.buffer).?;

        pass.setPipeline(pipeline);
        pass.setBindGroup(0, global_bind_group, null);
        pass.setVertexBuffer(0, buffer, 0, @sizeOf(LineRenderData) * @as(u32, @intCast(count)));
        pass.draw(6, @intCast(count), 0, 0);
    }
};
