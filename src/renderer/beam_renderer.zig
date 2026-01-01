const std = @import("std");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zglfw = @import("zglfw");
const shader_utils = @import("../shader_utils.zig");

const World = @import("../world.zig").World;
const Tile = @import("../tile.zig").Tile;
const Texture = @import("../texture.zig").Texture;
const Vec2 = @import("../vec2.zig").Vec2;
const GlobalRenderState = @import("common.zig").GlobalRenderState;
const packTileForGpu = @import("common.zig").packTileForGpu;

pub const BeamRenderer = struct {
    const Self = @This();
    const maxInstances = 512;

    allocator: std.mem.Allocator,
    gctx: *zgpu.GraphicsContext,
    pipeline_layout: zgpu.PipelineLayoutHandle,
    pipeline: zgpu.RenderPipelineHandle,
    buffer: zgpu.BufferHandle,

    pub const BeamRenderData = struct {
        start: [2]f32,
        end: [2]f32,
        width: f32,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        global: *GlobalRenderState,
    ) !Self {
        const instance_buffer = gctx.createBuffer(.{
            .usage = .{ .copy_dst = true, .vertex = true },
            .size = @sizeOf(BeamRenderData) * maxInstances,
        });

        const pipeline_layout = gctx.createPipelineLayout(&.{
            global.layout,
        });

        const pipeline = try createPipeline(
            gctx,
            pipeline_layout,
        );

        return .{
            .allocator = allocator,
            .gctx = gctx,
            .pipeline_layout = pipeline_layout,
            .pipeline = pipeline,
            .buffer = instance_buffer,
        };
    }

    pub fn deinit(self: Self) void {
        _ = self;
    }

    pub fn writeThrusters(self: *Self, world: *const World) !u32 {
        var beams = try self.allocator.alloc(BeamRenderData, maxInstances);
        defer self.allocator.free(beams);

        var count: usize = 0;

        for (world.objects.items) |*obj| {
            if (!obj.body_id.isValid()) continue;

            const cos_rot = @cos(obj.rotation);
            const sin_rot = @sin(obj.rotation);

            for (obj.thrusters.items) |thruster| {
                if (thruster.current_visual_power < 1.0) continue;
                if (count >= maxInstances) break;

                const local_x = thruster.x;
                const local_y = thruster.y;
                const world_offset_x = local_x * cos_rot - local_y * sin_rot;
                const world_offset_y = local_x * sin_rot + local_y * cos_rot;

                const start_x = obj.position.x + world_offset_x;
                const start_y = obj.position.y + world_offset_y;

                const local_dir = switch (thruster.direction) {
                    .north => Vec2.init(0.0, -1.0),
                    .south => Vec2.init(0.0, 1.0),
                    .east => Vec2.init(1.0, 0.0),
                    .west => Vec2.init(-1.0, 0.0),
                };

                const dir_x = local_dir.x * cos_rot - local_dir.y * sin_rot;
                const dir_y = local_dir.x * sin_rot + local_dir.y * cos_rot;

                const length = thruster.current_visual_power * 0.0012;
                const width = 3.0 + thruster.current_visual_power * 0.0001;

                const edge_offset = 4.0;
                const beam_start_x = start_x + dir_x * edge_offset;
                const beam_start_y = start_y + dir_y * edge_offset;

                beams[count] = .{
                    .start = .{ beam_start_x, beam_start_y },
                    .end = .{ beam_start_x + dir_x * length, beam_start_y + dir_y * length },
                    .width = width,
                };
                count += 1;
            }
        }

        if (count > 0) {
            self.gctx.queue.writeBuffer(
                self.gctx.lookupResource(self.buffer).?,
                0,
                u8,
                std.mem.sliceAsBytes(beams[0..count]),
            );
        }

        return @intCast(count);
    }

    pub fn draw(
        self: Self,
        pass: zgpu.wgpu.RenderPassEncoder,
        global: *const GlobalRenderState,
        instance_count: u32,
    ) void {
        if (instance_count == 0) {
            return;
        }

        const gctx = self.gctx;
        const pipeline = gctx.lookupResource(self.pipeline).?;
        const global_bind_group = gctx.lookupResource(global.bind_group).?;
        const buffer = gctx.lookupResource(self.buffer).?;

        pass.setPipeline(pipeline);
        pass.setBindGroup(0, global_bind_group, null);
        pass.setVertexBuffer(0, buffer, 0, @sizeOf(BeamRenderData) * instance_count);
        pass.draw(6, instance_count, 0, 0);
    }
};

fn createPipeline(
    gctx: *zgpu.GraphicsContext,
    pipeline_layout: zgpu.PipelineLayoutHandle,
) !zgpu.RenderPipelineHandle {
    const vs_module = shader_utils.createShaderModuleWithCommon(
        gctx.device,
        @embedFile("../shaders/beam_vertex.wgsl"),
        "vs_main",
    );
    defer vs_module.release();

    const fs_module = shader_utils.createShaderModuleWithCommon(
        gctx.device,
        @embedFile("../shaders/beam_fragment.wgsl"),
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
            .offset = @offsetOf(BeamRenderer.BeamRenderData, "start"),
            .shader_location = 0,
        },
        .{
            .format = .float32x2,
            .offset = @offsetOf(BeamRenderer.BeamRenderData, "end"),
            .shader_location = 1,
        },
        .{
            .format = .float32,
            .offset = @offsetOf(BeamRenderer.BeamRenderData, "width"),
            .shader_location = 2,
        },
    };

    const vertex_buffers = [_]wgpu.VertexBufferLayout{
        .{
            .array_stride = @sizeOf(BeamRenderer.BeamRenderData),
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

    return gctx.createRenderPipeline(pipeline_layout, pipeline_descriptor);
}
