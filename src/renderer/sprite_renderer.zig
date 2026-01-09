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
const TileObject = @import("../tile_object.zig").TileObject;

pub const GpuTileGrid = struct {
    texture: zgpu.TextureHandle,
    view: zgpu.TextureViewHandle,
    bind_group: zgpu.BindGroupHandle,
    width: u32,
    height: u32,
};

pub const SpriteRenderData = struct {
    wh: [4]f32,
    position: [4]f32,
    rotation: [4]f32,
    hover: [4]f32,
    scale: f32,
};

pub const SpriteRenderer = struct {
    const Self = @This();
    const maxInstances = 128;

    allocator: std.mem.Allocator,
    gctx: *zgpu.GraphicsContext,

    pipeline: zgpu.RenderPipelineHandle,
    texture_bind_group_layout: zgpu.BindGroupLayoutHandle,
    instance_buffer: zgpu.BufferHandle,

    instance_count: u32 = 0,

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

        return .{
            .allocator = allocator,
            .gctx = gctx,
            .pipeline = pipeline,
            .texture_bind_group_layout = layout,
            .instance_buffer = instance_buffer,
        };
    }

    pub fn deinit(self: Self) void {
        _ = self;
    }

    pub fn prepareObject(self: *Self, object: *TileObject) !void {
        if (object.gpu_grid == null) {
            const width: u32 = @intCast(object.width);
            const height: u32 = @intCast(object.height);

            const texture = self.gctx.createTexture(.{
                .usage = .{ .texture_binding = true, .copy_dst = true },
                .size = .{
                    .width = width,
                    .height = height,
                    .depth_or_array_layers = 1,
                },
                .format = wgpu.TextureFormat.r32_uint,
                .mip_level_count = 1,
            });
            const view = self.gctx.createTextureView(texture, .{});

            const bg = self.gctx.createBindGroup(self.texture_bind_group_layout, &.{
                .{ .binding = 0, .texture_view_handle = view },
            });

            object.gpu_grid = GpuTileGrid{
                .texture = texture,
                .view = view,
                .bind_group = bg,
                .width = width,
                .height = height,
            };

            object.dirty = true;
        }

        if (object.dirty) {
            const grid = object.gpu_grid.?;
            const data = try self.allocator.alloc(u32, object.width * object.height);
            defer self.allocator.free(data);

            for (0..object.width * object.height) |i| {
                const x = i % object.width;
                const y = i / object.width;

                data[i] = packTileForGpu(object.tiles[i], object.getNeighborMask(x, y), x, y);
            }

            self.gctx.queue.writeTexture(
                .{ .texture = self.gctx.lookupResource(grid.texture).? },
                .{ .bytes_per_row = grid.width * @sizeOf(u32), .rows_per_image = grid.height },
                .{ .width = grid.width, .height = grid.height },
                u32,
                data,
            );

            object.dirty = false;
        }
    }

    pub fn buildInstance(object: *const TileObject, hover_x: i32, hover_y: i32, highlight_all: bool) SpriteRenderData {
        return .{
            .wh = .{ @floatFromInt(object.width * 8), @floatFromInt(object.height * 8), 0, 0 },
            .position = .{ object.position.x, object.position.y, 0, 0 },
            .rotation = .{ object.rotation, 0, 0, 0 },
            .hover = .{
                @floatFromInt(hover_x),
                @floatFromInt(hover_y),
                if (hover_x >= 0) 1.0 else 0.0,
                if (highlight_all) 1.0 else 0.0,
            },
            .scale = 1.0,
        };
    }

    pub fn writeInstances(self: *Self, instances: []const SpriteRenderData) !void {
        if (instances.len > maxInstances) {
            return error.TooManyInstances;
        }

        self.instance_count = @intCast(instances.len);
        self.gctx.queue.writeBuffer(
            self.gctx.lookupResource(self.instance_buffer).?,
            0,
            u8,
            std.mem.sliceAsBytes(instances),
        );
    }

    pub fn draw(
        self: Self,
        pass: zgpu.wgpu.RenderPassEncoder,
        global: *const GlobalRenderState,
        objects: []TileObject,
    ) void {
        const pipeline = self.gctx.lookupResource(self.pipeline).?;
        const global_bind_group = self.gctx.lookupResource(global.bind_group).?;
        const buffer = self.gctx.lookupResource(self.instance_buffer).?;

        pass.setPipeline(pipeline);
        pass.setBindGroup(0, global_bind_group, null);

        pass.setVertexBuffer(0, buffer, 0, @sizeOf(SpriteRenderData) * self.instance_count);

        for (objects, 0..) |obj, i| {
            if (obj.gpu_grid) |grid| {
                const bg = self.gctx.lookupResource(grid.bind_group).?;

                pass.setBindGroup(1, bg, null);
                pass.draw(6, 1, 0, @intCast(i));
            }
        }
    }
};

fn createPipeline(
    gctx: *zgpu.GraphicsContext,
    pipeline_layout: zgpu.PipelineLayoutHandle,
) !zgpu.RenderPipelineHandle {
    const vs_module = shader_utils.createShaderModuleWithCommon(
        gctx.device,
        @embedFile("../shaders/sprite_vertex.wgsl"),
        "vs_main",
    );
    defer vs_module.release();

    const fs_module = shader_utils.createShaderModuleWithCommon(
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
            .offset = @offsetOf(SpriteRenderData, "wh"),
            .shader_location = 0,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(SpriteRenderData, "position"),
            .shader_location = 1,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(SpriteRenderData, "rotation"),
            .shader_location = 2,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(SpriteRenderData, "hover"),
            .shader_location = 3,
        },
        .{
            .format = .float32,
            .offset = @offsetOf(SpriteRenderData, "scale"),
            .shader_location = 4,
        },
    };

    const vertex_buffers = [_]wgpu.VertexBufferLayout{
        .{
            .array_stride = @sizeOf(SpriteRenderData),
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
