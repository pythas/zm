const std = @import("std");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zglfw = @import("zglfw");

const World = @import("../world.zig").World;
const Tile = @import("../tile.zig").Tile;
const TileType = @import("../tile.zig").TileType;
const Texture = @import("../texture.zig").Texture;
const GameMode = @import("../game.zig").GameMode;

pub const GlobalUniforms = extern struct {
    dt: f32,
    t: f32,
    mode: u32,
    _pad0: f32,
    screen_wh: [4]f32,
    camera_xy: [4]f32,
    camera_zoom: f32,
    _pad_removed_tile_size: f32,
    _pad1: f32,
    _pad2: f32,
    hover_xy: [4]f32,
};

pub const GlobalRenderState = struct {
    const Self = @This();

    gctx: *zgpu.GraphicsContext,
    layout: zgpu.BindGroupLayoutHandle,
    buffer: zgpu.BufferHandle,
    bind_group: zgpu.BindGroupHandle,

    pub fn init(
        gctx: *zgpu.GraphicsContext,
        atlas_view: zgpu.TextureViewHandle,
    ) !Self {
        const sampler = gctx.createSampler(.{
            .mag_filter = .nearest,
            .min_filter = .nearest,
        });

        const layout = gctx.createBindGroupLayout(&.{
            zgpu.bufferEntry(0, .{ .vertex = true, .fragment = true }, .uniform, false, 0),
            zgpu.textureEntry(2, .{ .fragment = true }, .float, .tvdim_2d_array, false),
            zgpu.samplerEntry(3, .{ .fragment = true }, .filtering),
        });

        const buffer = gctx.createBuffer(.{
            .usage = .{ .copy_dst = true, .uniform = true },
            .size = 256,
        });

        const bind_group = gctx.createBindGroup(layout, &.{
            .{ .binding = 0, .buffer_handle = buffer, .offset = 0, .size = 256 },
            .{ .binding = 2, .texture_view_handle = atlas_view },
            .{ .binding = 3, .sampler_handle = sampler },
        });

        return .{
            .gctx = gctx,
            .layout = layout,
            .buffer = buffer,
            .bind_group = bind_group,
        };
    }

    pub fn write(
        self: Self,
        window: *zglfw.Window,
        world: *const World,
        dt: f32,
        t: f32,
        mode: GameMode,
        hover_x: i32,
        hover_y: i32,
    ) void {
        const wh = window.getFramebufferSize();

        var uniform_data = GlobalUniforms{
            .dt = dt,
            .t = t,
            .mode = @intFromEnum(mode),
            ._pad0 = 0.0,
            .screen_wh = .{ @floatFromInt(wh[0]), @floatFromInt(wh[1]), 0, 0 },
            .camera_xy = .{ world.camera.position.x, world.camera.position.y, 0, 0 },
            .camera_zoom = world.camera.zoom,
            ._pad_removed_tile_size = 1.0,
            ._pad1 = 0.0,
            ._pad2 = 0.0,
            .hover_xy = .{
                @floatFromInt(hover_x),
                @floatFromInt(hover_y),
                if (hover_x >= 0) 1.0 else 0.0,
                0,
            },
        };

        self.gctx.queue.writeBuffer(
            self.gctx.lookupResource(self.buffer).?,
            0,
            u8,
            std.mem.asBytes(&uniform_data),
        );
    }

    pub fn deinit(self: *GlobalRenderState) void {
        _ = self;
    }
};

pub const Atlas = struct {
    texture: zgpu.TextureHandle,
    view: zgpu.TextureViewHandle,

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        paths: []const []const u8,
    ) !Atlas {
        const layers = paths.len;

        const texture = gctx.createTexture(.{
            .usage = .{ .texture_binding = true, .copy_dst = true },
            .size = .{
                .width = 256,
                .height = 256,
                .depth_or_array_layers = @intCast(layers),
            },
            .format = wgpu.TextureFormat.rgba8_unorm,
            .mip_level_count = 1,
        });

        const view = gctx.createTextureView(texture, .{
            .dimension = .tvdim_2d_array,
            .array_layer_count = @intCast(layers),
        });

        const texture_size = 256 * 256 * 4;
        var texture_data = try allocator.alloc(u8, texture_size);
        defer allocator.free(texture_data);

        for (paths, 0..) |path, i| {
            const tex = try Texture.init(allocator, path);
            defer tex.deinit();
            @memcpy(texture_data[0..texture_size], tex.data);

            gctx.queue.writeTexture(
                .{
                    .texture = gctx.lookupResource(texture).?,
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

        return .{
            .texture = texture,
            .view = view,
        };
    }

    pub fn deinit(self: *Atlas) void {
        _ = self;
    }
};

pub fn packTileForGpu(tile: Tile) u32 {
    const sheet: u32 = @intFromEnum(tile.sprite.sheet) & 0x0F; // 4 bits
    const tile_type_id: u32 = @as(u32, @intFromEnum(@as(TileType, tile.data))) & 0x0F; // 4 bits
    const sprite_index: u32 = tile.sprite.index & 0x03FF; // 10 bits

    return (sheet << 14) | (tile_type_id << 10) | sprite_index;
}
