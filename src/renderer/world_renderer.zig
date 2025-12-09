const std = @import("std");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zglfw = @import("zglfw");
const shader_utils = @import("../shader_utils.zig");

const World = @import("../world.zig").World;
const Tile = @import("../tile.zig").Tile;
const Texture = @import("../texture.zig").Texture;
const GlobalRenderState = @import("common.zig").GlobalRenderState;
const packTileForGpu = @import("common.zig").packTileForGpu;

pub const ChunkUniforms = extern struct {
    chunk_xy: [4]f32,
    chunk_wh: [4]f32,
};

pub const WorldRenderer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    gctx: *zgpu.GraphicsContext,
    window: *zglfw.Window,
    global: *GlobalRenderState,
    pipeline_layout: zgpu.PipelineLayoutHandle,
    pipeline: zgpu.RenderPipelineHandle,
    chunk_bind_group_layout: zgpu.BindGroupLayoutHandle,

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        window: *zglfw.Window,
        global: *GlobalRenderState,
    ) !Self {
        const chunk_bind_group_layout = gctx.createBindGroupLayout(&.{
            zgpu.bufferEntry(0, .{ .vertex = true, .fragment = true }, .uniform, false, 0),
            zgpu.textureEntry(1, .{ .fragment = true }, .uint, .tvdim_2d, false),
        });

        const pipeline_layout = gctx.createPipelineLayout(&.{
            global.layout,
            chunk_bind_group_layout,
        });

        const pipeline = try createPipeline(
            gctx,
            pipeline_layout,
        );

        return .{
            .allocator = allocator,
            .gctx = gctx,
            .window = window,
            .global = global,
            .pipeline_layout = pipeline_layout,
            .pipeline = pipeline,
            .chunk_bind_group_layout = chunk_bind_group_layout,
        };
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }

    pub fn writeTextures(self: Self, world: *const World) !void {
        _ = self;
        _ = world;
    }

    pub fn draw(
        self: Self,
        pass: zgpu.wgpu.RenderPassEncoder,
        global: *const GlobalRenderState,
        world: *const World,
    ) void {
        {
            const pipeline = self.gctx.lookupResource(self.pipeline).?;
            const bind_group = self.gctx.lookupResource(global.bind_group).?;

            pass.setPipeline(pipeline);
            pass.setBindGroup(0, bind_group, null);
        }

        // TODO: for each visible chunk
        for (world.map.chunks.items) |chunk| {
            const render_data = chunk.render_data orelse continue;
            const bind_group = self.gctx.lookupResource(render_data.bind_group).?;

            self.writeChunkBuffers(chunk);

            pass.setBindGroup(1, bind_group, null);
            pass.draw(6, 1, 0, 0);
        }
    }
};

fn createPipeline(
    gctx: *zgpu.GraphicsContext,
    pipeline_layout: zgpu.PipelineLayoutHandle,
) !zgpu.RenderPipelineHandle {
    const vs_module = shader_utils.createShaderModuleWithCommon(
        gctx.device,
        @embedFile("../shaders/world_vertex.wgsl"),
        "vs_main",
    );
    defer vs_module.release();

    const fs_module = shader_utils.createShaderModuleWithCommon(
        gctx.device,
        @embedFile("../shaders/world_fragment.wgsl"),
        "fs_main",
    );
    defer fs_module.release();

    const color_targets = [_]wgpu.ColorTargetState{
        .{ .format = gctx.swapchain_descriptor.format },
    };

    const pipeline_descriptor = wgpu.RenderPipelineDescriptor{
        .vertex = .{
            .module = vs_module,
            .entry_point = "main",
            .buffer_count = 0,
            .buffers = null,
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
