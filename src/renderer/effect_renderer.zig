const std = @import("std");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zglfw = @import("zglfw");

const World = @import("../world.zig").World;
const Map = @import("../map.zig").Map;
const Tile = @import("../tile.zig").Tile;
const Chunk = @import("../chunk.zig").Chunk;
const Texture = @import("../texture.zig").Texture;
const Player = @import("../player.zig").Player;
const GlobalRenderState = @import("common.zig").GlobalRenderState;

pub const EffectRenderer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    gctx: *zgpu.GraphicsContext,
    global: *GlobalRenderState,
    pipeline_layout: zgpu.PipelineLayoutHandle,
    pipeline: zgpu.RenderPipelineHandle,

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        global: *GlobalRenderState,
    ) !Self {
        const layout = gctx.createBindGroupLayout(&.{
            zgpu.bufferEntry(0, .{ .vertex = true, .fragment = true }, .uniform, false, 0),
            zgpu.textureEntry(1, .{ .fragment = true }, .uint, .tvdim_2d, false),
        });

        const pipeline_layout = gctx.createPipelineLayout(&.{
            global.layout,
            layout,
        });

        const pipeline = try createPipeline(
            gctx,
            pipeline_layout,
        );

        return .{
            .allocator = allocator,
            .gctx = gctx,
            .global = global,
            .pipeline_layout = pipeline_layout,
            .pipeline = pipeline,
        };
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }

    pub fn draw(
        self: Self,
        pass: zgpu.wgpu.RenderPassEncoder,
        global: *const GlobalRenderState,
    ) void {
        const pipeline = self.gctx.lookupResource(self.pipeline).?;
        const bind_group = self.gctx.lookupResource(global.bind_group).?;

        pass.setPipeline(pipeline);
        pass.setBindGroup(0, bind_group, null);

        pass.draw(6, 1, 0, 0);
    }
};

fn createPipeline(
    gctx: *zgpu.GraphicsContext,
    pipeline_layout: zgpu.PipelineLayoutHandle,
) !zgpu.RenderPipelineHandle {
    const vs_module = zgpu.createWgslShaderModule(
        gctx.device,
        @embedFile("../shaders/effect_vertex.wgsl"),
        "vs_main",
    );
    defer vs_module.release();

    const fs_module = zgpu.createWgslShaderModule(
        gctx.device,
        @embedFile("../shaders/effect_fragment.wgsl"),
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
