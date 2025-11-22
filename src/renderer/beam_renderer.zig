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
const Vec2 = @import("../vec2.zig").Vec2;
const GlobalRenderState = @import("common.zig").GlobalRenderState;
const packTileForGpu = @import("common.zig").packTileForGpu;

pub const BeamRenderer = struct {
    const Self = @This();
    const maxInstances = 128;

    allocator: std.mem.Allocator,
    gctx: *zgpu.GraphicsContext,
    pipeline_layout: zgpu.PipelineLayoutHandle,
    pipeline: zgpu.RenderPipelineHandle,
    buffer: zgpu.BufferHandle,

    pub const BeamRenderData = struct {
        start: [2]f32,
        end: [2]f32,
        width: f32,
        intensity: f32,
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

    pub fn writeBuffers(self: *Self, world: *const World) !u32 {
        const player = &world.player;
        const actions = player.tile_actions.items;

        // How many beams do we actually need?
        var active_count: usize = 0;
        for (actions) |action| {
            if (action.isActive() and action.kind == .Mine) {
                active_count += 1;
            }
        }

        if (active_count == 0) {
            // No beams → nothing to write
            return 0;
        }

        const count = @min(active_count, maxInstances);
        var beams = try self.allocator.alloc(BeamRenderData, count);
        defer self.allocator.free(beams);

        var bi: usize = 0;
        for (actions) |action| {
            if (!action.isActive() or action.kind != .Mine) continue;
            if (bi >= count) break;

            const p = action.getProgress();

            const start = player.position;

            const tile_world_pos = action.tile_ref.worldCenter();
            const tile_size = @as(f32, @floatFromInt(Tile.tileSize));
            const tile_pos = Vec2.init(tile_world_pos.x / tile_size, tile_world_pos.y / tile_size);

            const base_width: f32 = 6.0;
            const extra_pulse: f32 = 2.0 * @sin(p * std.math.pi);
            const width: f32 = base_width + extra_pulse;

            beams[bi] = .{
                .start = .{ start.x, start.y },
                .end = .{ tile_pos.x, tile_pos.y },
                .width = width,
                .intensity = p,
            };

            bi += 1;
        }

        if (bi == 0) return 0;

        self.gctx.queue.writeBuffer(
            self.gctx.lookupResource(self.buffer).?,
            0,
            u8,
            std.mem.sliceAsBytes(beams[0..bi]),
        );

        return @intCast(bi);
    }

    // pub fn writeBuffers(self: *Self, world: *const World) !void {
    //     const count = 1;
    //
    //     var beams = try self.allocator.alloc(BeamRenderData, count);
    //     defer self.allocator.free(beams);
    //
    //     beams[0] = .{
    //         .start = .{ world.player.position.x, world.player.position.y },
    //         .end = .{ 10, 10 },
    //         .width = 8.0,
    //         .intensity = 1.0,
    //     };
    //
    //     self.gctx.queue.writeBuffer(
    //         self.gctx.lookupResource(self.buffer).?,
    //         0,
    //         u8,
    //         std.mem.sliceAsBytes(beams),
    //     );
    // }

    pub fn draw(
        self: Self,
        pass: zgpu.wgpu.RenderPassEncoder,
        global: *const GlobalRenderState,
        instance_count: u32,
    ) void {
        if (instance_count == 0) return;

        const gctx = self.gctx;
        const pipeline = gctx.lookupResource(self.pipeline).?;
        const global_bind_group = gctx.lookupResource(global.bind_group).?;
        const buffer = gctx.lookupResource(self.buffer).?;

        pass.setPipeline(pipeline);
        pass.setBindGroup(0, global_bind_group, null);
        pass.setVertexBuffer(0, buffer, 0, @sizeOf(BeamRenderData) * instance_count);
        pass.draw(6, instance_count, 0, 0);
    }

    // pub fn draw(
    //     self: Self,
    //     pass: zgpu.wgpu.RenderPassEncoder,
    //     global: *const GlobalRenderState,
    // ) void {
    //     const gctx = self.gctx;
    //     const pipeline = gctx.lookupResource(self.pipeline).?;
    //     const global_bind_group = gctx.lookupResource(global.bind_group).?;
    //     const buffer = gctx.lookupResource(self.buffer).?;
    //
    //     const count = 1;
    //
    //     pass.setPipeline(pipeline);
    //     pass.setBindGroup(0, global_bind_group, null);
    //     pass.setVertexBuffer(0, buffer, 0, @sizeOf(BeamRenderData) * count);
    //     pass.draw(6, count, 0, 0);
    // }
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
