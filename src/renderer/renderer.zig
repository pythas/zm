const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");

const Atlas = @import("common.zig").Atlas;
const GlobalRenderState = @import("common.zig").GlobalRenderState;
const WorldRenderer = @import("world_renderer.zig").WorldRenderer;
const SpriteRenderer = @import("sprite_renderer.zig").SpriteRenderer;
const World = @import("../world.zig").World;

pub const Renderer = struct {
    const Self = @This();

    atlas: Atlas,
    global: GlobalRenderState,
    world: WorldRenderer,
    sprite: SpriteRenderer,

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        window: *zglfw.Window,
    ) !Self {
        const atlas = try Atlas.init(allocator, gctx, &.{
            "assets/world.png",
            "assets/asteroid.png",
            "assets/ship.png",
        });

        var global = try GlobalRenderState.init(gctx, atlas.view);
        const world = try WorldRenderer.init(allocator, gctx, window, &global);
        const sprite = try SpriteRenderer.init(allocator, gctx, &global);

        return .{
            .atlas = atlas,
            .global = global,
            .world = world,
            .sprite = sprite,
        };
    }

    pub fn update(
        self: Self,
        window: *zglfw.Window,
        world: *World,
        dt: f32,
        t: f32,
    ) void {
        self.global.write(window, world, dt, t);
    }

    pub fn draw(
        self: *Self,
        pass: zgpu.wgpu.RenderPassEncoder,
        world: *World,
    ) !void {
        try self.world.writeTextures(world);
        self.world.draw(pass, &self.global, world);

        try self.sprite.writeBuffers(world);
        self.sprite.draw(pass, &self.global);
    }
};
