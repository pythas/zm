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
const packTileForGpu = @import("common.zig").packTileForGpu;

pub const SpriteRenderer = struct {
    const Self = @This();
    const maxInstances = 128;

    allocator: std.mem.Allocator,
    gctx: *zgpu.GraphicsContext,
    pipeline_layout: zgpu.PipelineLayoutHandle,
    pipeline: zgpu.RenderPipelineHandle,
    buffer: zgpu.BufferHandle,
    tilemap: zgpu.TextureHandle,
    bind_group: zgpu.BindGroupHandle,

    pub const SpriteRenderData = struct {
        wh: [4]f32,
        position: [4]f32,
        rotation: [4]f32,
    };

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        global: *GlobalRenderState,
    ) !Self {
        const instance_buffer = gctx.createBuffer(.{
            .usage = .{ .copy_dst = true, .vertex = true },
            .size = @sizeOf(SpriteRenderData) * maxInstances,
        });

        const layout = gctx.createBindGroupLayout(&.{
            zgpu.textureEntry(0, .{ .fragment = true }, .uint, .tvdim_2d, false),
        });

        const pipeline_layout = gctx.createPipelineLayout(&.{
            global.layout,
            layout,
        });

        const pipeline = try createPipeline(
            gctx,
            pipeline_layout,
        );

        const tilemap = gctx.createTexture(.{
            .usage = .{ .texture_binding = true, .copy_dst = true },
            .size = .{
                .width = 8,
                .height = 8,
                .depth_or_array_layers = 1,
            },
            .format = wgpu.TextureFormat.r32_uint,
            .mip_level_count = 1,
        });
        const tilemap_view = gctx.createTextureView(tilemap, .{});

        const bind_group = gctx.createBindGroup(layout, &.{
            .{ .binding = 0, .texture_view_handle = tilemap_view },
        });

        return .{
            .allocator = allocator,
            .gctx = gctx,
            .pipeline_layout = pipeline_layout,
            .pipeline = pipeline,
            .buffer = instance_buffer,
            .tilemap = tilemap,
            .bind_group = bind_group,
        };
    }

    pub fn deinit(self: Self) void {
        _ = self;
    }

    pub fn writeBuffers(self: *Self, world: *const World) !void {
        const count = 1;

        var sprites = try self.allocator.alloc(SpriteRenderData, count);
        defer self.allocator.free(sprites);

        // player
        sprites[0] = .{
            .wh = .{ Player.playerWidth, Player.playerHeight, 0, 0 },
            .position = .{ world.player.position.x, world.player.position.y, 0, 0 },
            .rotation = .{ world.player.rotation, 0, 0, 0 },
        };

        self.gctx.queue.writeBuffer(
            self.gctx.lookupResource(self.buffer).?,
            0,
            u8,
            std.mem.sliceAsBytes(sprites),
        );
    }

    pub fn writeTilemap(self: *Self, world: *const World) !void {
        const width = 8;
        const height = 8;

        const data = try self.allocator.alloc(u32, width * height);
        defer self.allocator.free(data);

        for (0..height) |y| {
            for (0..width) |x| {
                data[y * width + x] = 0;
            }
        }

        for (0..Player.playerHeight) |y| {
            for (0..Player.playerWidth) |x| {
                const tile = world.player.tiles[@intCast(x)][@intCast(y)];
                const id = packTileForGpu(tile);
                data[(y * width) + x] = id;
            }
        }

        self.gctx.queue.writeTexture(
            .{ .texture = self.gctx.lookupResource(self.tilemap).? },
            .{ .bytes_per_row = width * @sizeOf(u32), .rows_per_image = height },
            .{ .width = width, .height = height },
            u32,
            data,
        );
    }

    pub fn draw(
        self: Self,
        pass: zgpu.wgpu.RenderPassEncoder,
        global: *const GlobalRenderState,
    ) void {
        const gctx = self.gctx;
        const pipeline = gctx.lookupResource(self.pipeline).?;
        const global_bind_group = gctx.lookupResource(global.bind_group).?;
        const bind_group = gctx.lookupResource(self.bind_group).?;
        const buffer = gctx.lookupResource(self.buffer).?;

        const count = 1;

        pass.setPipeline(pipeline);
        pass.setBindGroup(0, global_bind_group, null);
        pass.setBindGroup(1, bind_group, null);
        pass.setVertexBuffer(0, buffer, 0, @sizeOf(SpriteRenderData) * count);
        pass.draw(6, 1, 0, 0);
    }
};

fn createPipeline(
    gctx: *zgpu.GraphicsContext,
    pipeline_layout: zgpu.PipelineLayoutHandle,
) !zgpu.RenderPipelineHandle {
    const vs_module = zgpu.createWgslShaderModule(
        gctx.device,
        @embedFile("../shaders/sprite_vertex.wgsl"),
        "vs_main",
    );
    defer vs_module.release();

    const fs_module = zgpu.createWgslShaderModule(
        gctx.device,
        @embedFile("../shaders/sprite_fragment.wgsl"),
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
            .format = .float32x4,
            .offset = @offsetOf(SpriteRenderer.SpriteRenderData, "wh"),
            .shader_location = 0,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(SpriteRenderer.SpriteRenderData, "position"),
            .shader_location = 1,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(SpriteRenderer.SpriteRenderData, "rotation"),
            .shader_location = 2,
        },
    };

    const vertex_buffers = [_]wgpu.VertexBufferLayout{
        .{
            .array_stride = @sizeOf(SpriteRenderer.SpriteRenderData),
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
