const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");

const Atlas = @import("common.zig").Atlas;
const GlobalRenderState = @import("common.zig").GlobalRenderState;
const SpriteRenderer = @import("sprite_renderer.zig").SpriteRenderer;
const EffectRenderer = @import("effect_renderer.zig").EffectRenderer;
const BeamRenderer = @import("beam_renderer.zig").BeamRenderer;
const UiRenderer = @import("ui_renderer.zig").UiRenderer;
const World = @import("../world.zig").World;

pub const Renderer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    atlas: Atlas,
    global: GlobalRenderState,
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
            "assets/asteroid.png",
            "assets/ship.png",
            "assets/resource.png",
            "assets/tool.png",
        });

        var global = try GlobalRenderState.init(gctx, atlas.view);
        const sprite = try SpriteRenderer.init(allocator, gctx, &global);
        const effect = try EffectRenderer.init(allocator, gctx, &global);
        const beam = try BeamRenderer.init(allocator, gctx, &global);
        const ui = try UiRenderer.init(allocator, gctx, window, &global);

        return .{
            .allocator = allocator,
            .atlas = atlas,
            .global = global,
            .sprite = sprite,
            .effect = effect,
            .beam = beam,
            .ui = ui,
        };
    }

    pub fn deinit(self: *Self) void {
        self.atlas.deinit();
        self.global.deinit();
        self.sprite.deinit();
        self.effect.deinit();
        self.beam.deinit();
        self.ui.deinit();
    }
};
