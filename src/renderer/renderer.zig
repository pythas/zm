const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");

const Atlas = @import("common.zig").Atlas;
const GlobalRenderState = @import("common.zig").GlobalRenderState;
const WorldRenderer = @import("world_renderer.zig").WorldRenderer;
const SpriteRenderer = @import("sprite_renderer.zig").SpriteRenderer;
const EffectRenderer = @import("effect_renderer.zig").EffectRenderer;
const BeamRenderer = @import("beam_renderer.zig").BeamRenderer;
const UiRenderer = @import("ui_renderer.zig").UiRenderer;
const World = @import("../world.zig").World;

pub const Renderer = struct {
    const Self = @This();

    atlas: Atlas,
    global: GlobalRenderState,
    world: WorldRenderer,
    sprite: SpriteRenderer,
    effect: EffectRenderer,
    beam: BeamRenderer,
    ui: UiRenderer,

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
        const effect = try EffectRenderer.init(allocator, gctx, &global);
        const beam = try BeamRenderer.init(allocator, gctx, &global);
        const ui = try UiRenderer.init(allocator, gctx, &global);

        return .{
            .atlas = atlas,
            .global = global,
            .world = world,
            .sprite = sprite,
            .effect = effect,
            .beam = beam,
            .ui = ui,
        };
    }

    // pub fn update(
    //     self: Self,
    //     window: *zglfw.Window,
    //     world: *World,
    //     dt: f32,
    //     t: f32,
    // ) void {
    //     self.global.write(window, world, dt, t);
    // }

    // pub fn draw(
    //     self: *Self,
    //     pass: zgpu.wgpu.RenderPassEncoder,
    //     world: *World,
    // ) !void {
    //     try self.world.writeTextures(world);
    //     self.world.draw(pass, &self.global, world);
    //
    //     // try self.sprite.writeBuffers(world);
    //     self.sprite.draw(pass, &self.global);
    //
    //     const beam_instance_count = try self.beam.writeBuffers(world);
    //     self.beam.draw(pass, &self.global, beam_instance_count);
    // }
};
