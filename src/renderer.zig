const std = @import("std");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zglfw = @import("zglfw");

const World = @import("world.zig").World;
const Map = @import("map.zig").Map;
const Tile = @import("map.zig").Tile;
const Chunk = @import("map.zig").Chunk;
const Texture = @import("texture.zig").Texture;
const Player = @import("player.zig").Player;

pub const GlobalRenderState = struct {
    const Self = @This();

    layout: zgpu.BindGroupLayoutHandle,
    buffer: zgpu.BufferHandle,
    bind_group: zgpu.BindGroupHandle,

    pub fn init(allocator: std.mem.Allocator, gctx: *zgpu.GraphicsContext) !Self {
        const sampler = createSampler(gctx);

        const layout = gctx.createBindGroupLayout(&.{
            zgpu.bufferEntry(0, .{ .vertex = true, .fragment = true }, .uniform, false, 0),
            zgpu.textureEntry(2, .{ .fragment = true }, .float, .tvdim_2d_array, false),
            zgpu.samplerEntry(3, .{ .fragment = true }, .filtering),
        });

        const buffer = gctx.createBuffer(.{
            .usage = .{ .copy_dst = true, .uniform = true },
            .size = 256,
        });

        // atlas
        const atlas = gctx.createTexture(.{
            .usage = .{ .texture_binding = true, .copy_dst = true },
            .size = .{
                .width = 256,
                .height = 256,
                .depth_or_array_layers = 16,
            },
            .format = zgpu.wgpu.TextureFormat.rgba8_unorm,
            .mip_level_count = 1,
        });

        const atlas_view = gctx.createTextureView(atlas, .{
            .dimension = .tvdim_2d_array,
            .array_layer_count = 16,
        });

        // tmp: write atlas stuff
        const texture_size = 256 * 256 * 4;

        var texture_data = try allocator.alloc(u8, texture_size);
        defer allocator.free(texture_data);

        const texture_paths = [_][]const u8{
            "assets/world.png",
            "assets/asteroid.png",
            "assets/ship.png",
        };

        for (texture_paths, 0..) |texture_path, i| {
            const texture = try Texture.init(allocator, texture_path);

            @memcpy(texture_data[0..texture_size], texture.data);

            gctx.queue.writeTexture(
                .{
                    .texture = gctx.lookupResource(atlas).?,
                    .mip_level = 0,
                    .origin = .{ .x = 0, .y = 0, .z = @intCast(i) },
                },
                .{
                    .bytes_per_row = 256 * 4,
                    .rows_per_image = 256,
                },
                .{
                    .width = 256,
                    .height = 256,
                    .depth_or_array_layers = 1,
                },
                u8,
                texture_data[0..texture_size],
            );
        }

        const bind_group = gctx.createBindGroup(layout, &.{
            .{ .binding = 0, .buffer_handle = buffer, .offset = 0, .size = 256 },
            .{ .binding = 2, .texture_view_handle = atlas_view },
            .{ .binding = 3, .sampler_handle = sampler },
        });

        return .{
            .layout = layout,
            .buffer = buffer,
            .bind_group = bind_group,
        };
    }

    pub fn write(self: Self, gctx: *zgpu.GraphicsContext, window: *zglfw.Window, world: *const World, dt: f32, t: f32) void {
        const wh = window.getFramebufferSize();

        var uniform_data = WorldRenderer.GlobalUniforms{
            .dt = dt,
            .t = t,
            ._pad0 = 0.0,
            ._pad1 = 0.0,
            .screen_wh = .{ @floatFromInt(wh[0]), @floatFromInt(wh[1]), 0, 0 },
            .camera_xy = .{ world.camera.position.x, world.camera.position.y, 0, 0 },
            .camera_zoom = world.camera.zoom,
            .tile_size = Tile.tileSize,
        };

        gctx.queue.writeBuffer(
            gctx.lookupResource(self.buffer).?,
            0,
            u8,
            std.mem.asBytes(&uniform_data),
        );
    }
};

pub const WorldRenderer = struct {
    const Self = @This();

    pub const GlobalUniforms = extern struct {
        dt: f32,
        t: f32,
        _pad0: f32,
        _pad1: f32,

        screen_wh: [4]f32,
        camera_xy: [4]f32,
        camera_zoom: f32,
        tile_size: f32,
    };

    pub const ChunkUniforms = extern struct {
        chunk_xy: [4]f32,
        chunk_wh: [4]f32,
    };

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

        const pipeline = try createWorldPipeline(
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

    pub fn writeChunkBuffers(self: Self, chunk: Chunk) void {
        const render_data = chunk.render_data orelse return;

        var uniform_data = ChunkUniforms{
            .chunk_xy = .{ @floatFromInt(chunk.x), @floatFromInt(chunk.y), 0, 0 },
            .chunk_wh = .{ @floatFromInt(Chunk.chunkWidth), @floatFromInt(Chunk.chunkHeight), 0, 0 },
        };

        self.gctx.queue.writeBuffer(
            self.gctx.lookupResource(render_data.uniform_buffer).?,
            0,
            u8,
            std.mem.asBytes(&uniform_data),
        );
    }

    pub fn createChunkRenderData(self: Self, chunk: *Chunk) !void {
        const tilemap = self.gctx.createTexture(.{
            .usage = .{ .texture_binding = true, .copy_dst = true },
            .size = .{
                .width = Chunk.chunkWidth,
                .height = Chunk.chunkHeight,
                .depth_or_array_layers = 1,
            },
            .format = wgpu.TextureFormat.r32_uint,
            .mip_level_count = 1,
        });
        const tilemap_view = self.gctx.createTextureView(tilemap, .{});

        const uniform_buffer = self.gctx.createBuffer(.{
            .usage = .{ .copy_dst = true, .uniform = true },
            .size = @sizeOf(ChunkUniforms),
        });

        const bind_group = self.gctx.createBindGroup(self.chunk_bind_group_layout, &.{
            .{ .binding = 0, .buffer_handle = uniform_buffer, .offset = 0, .size = @sizeOf(ChunkUniforms) },
            .{ .binding = 1, .texture_view_handle = tilemap_view },
        });

        const chunk_data = try self.allocator.alloc(u32, Chunk.chunkWidth * Chunk.chunkHeight);
        defer self.allocator.free(chunk_data);

        for (0..Chunk.chunkHeight) |y| {
            for (0..Chunk.chunkWidth) |x| {
                const tile = chunk.tiles[x][y];
                const id = packTileForGpu(tile);
                chunk_data[(y * Chunk.chunkWidth) + x] = id;
            }
        }

        self.gctx.queue.writeTexture(
            .{ .texture = self.gctx.lookupResource(tilemap).? },
            .{ .bytes_per_row = Chunk.chunkWidth * @sizeOf(u32), .rows_per_image = Chunk.chunkHeight },
            .{ .width = Chunk.chunkWidth, .height = Chunk.chunkHeight },
            u32,
            chunk_data,
        );

        chunk.render_data = .{
            .tilemap = tilemap,
            .tilemap_view = tilemap_view,
            .uniform_buffer = uniform_buffer,
            .bind_group = bind_group,
        };
    }
};

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

        const pipeline = try createSpritePipeline(
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

    pub fn draw(self: Self, pass: zgpu.wgpu.RenderPassEncoder, global: *const GlobalRenderState) void {
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

fn createWorldPipeline(
    gctx: *zgpu.GraphicsContext,
    pipeline_layout: zgpu.PipelineLayoutHandle,
) !zgpu.RenderPipelineHandle {
    const vs_module = zgpu.createWgslShaderModule(
        gctx.device,
        @embedFile("shaders/world_vertex.wgsl"),
        "vs_main",
    );
    defer vs_module.release();

    const fs_module = zgpu.createWgslShaderModule(
        gctx.device,
        @embedFile("shaders/world_fragment.wgsl"),
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

fn createSpritePipeline(
    gctx: *zgpu.GraphicsContext,
    pipeline_layout: zgpu.PipelineLayoutHandle,
) !zgpu.RenderPipelineHandle {
    const vs_module = zgpu.createWgslShaderModule(
        gctx.device,
        @embedFile("shaders/sprite_vertex.wgsl"),
        "vs_main",
    );
    defer vs_module.release();

    const fs_module = zgpu.createWgslShaderModule(
        gctx.device,
        @embedFile("shaders/sprite_fragment.wgsl"),
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

fn createSampler(gctx: *zgpu.GraphicsContext) zgpu.SamplerHandle {
    return gctx.createSampler(.{
        .mag_filter = .nearest,
        .min_filter = .nearest,
    });
}

fn packTileForGpu(tile: Tile) u32 {
    const sheet_bits: u32 = @intFromEnum(tile.sheet) & 0x0F; // 4 bits
    const kind_bits: u32 = @intFromEnum(tile.kind) & 0x0F; // 4 bits
    const sprite_bits: u32 = tile.sprite & 0x03FF; // 10 bits

    return (sheet_bits << 14) | (kind_bits << 10) | sprite_bits;
}
