const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");

const Atlas = @import("renderer/common.zig").Atlas;
const AtlasLayer = @import("renderer/common.zig").AtlasLayer;
const GlobalRenderState = @import("renderer/common.zig").GlobalRenderState;
const SpriteRenderer = @import("renderer/sprite_renderer.zig").SpriteRenderer;
const BackgroundRenderer = @import("renderer/background_renderer.zig").BackgroundRenderer;
const BeamRenderer = @import("renderer/beam_renderer.zig").BeamRenderer;
const LineRenderer = @import("renderer/line_renderer.zig").LineRenderer;
const UiRenderer = @import("renderer/ui_renderer.zig").UiRenderer;
const World = @import("world.zig").World;
const Font = @import("renderer/font.zig").Font;

pub const Renderer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    atlas: Atlas,
    global: GlobalRenderState,
    sprite: SpriteRenderer,
    background: BackgroundRenderer,
    beam: BeamRenderer,
    line: LineRenderer,
    ui: UiRenderer,
    font: *Font,

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        window: *zglfw.Window,
    ) !Self {
        const font = try allocator.create(Font);
        font.* = try Font.init(allocator, "assets/spleen-6x12.bdf");

        const atlas = try Atlas.init(allocator, gctx, &.{
            .{ .raw = font.texture_data },
            .{ .path = "assets/asteroid.png" },
            .{ .path = "assets/ship.png" },
            .{ .path = "assets/resource.png" },
            .{ .path = "assets/tool.png" },
            .{ .path = "assets/recipe.png" },
        });

        var global = try GlobalRenderState.init(gctx, atlas.view);
        const sprite = try SpriteRenderer.init(allocator, gctx, &global);
        const background = try BackgroundRenderer.init(allocator, gctx, &global);
        const beam = try BeamRenderer.init(allocator, gctx, &global);
        const line = try LineRenderer.init(allocator, gctx, &global);
        const ui = try UiRenderer.init(allocator, gctx, window, &global);

        return .{
            .allocator = allocator,
            .atlas = atlas,
            .global = global,
            .sprite = sprite,
            .background = background,
            .beam = beam,
            .line = line,
            .ui = ui,
            .font = font,
        };
    }

    pub fn deinit(self: *Self) void {
        self.atlas.deinit();
        self.global.deinit();
        self.sprite.deinit();
        self.background.deinit();
        self.beam.deinit();
        self.line.deinit();
        self.ui.deinit();
        self.font.deinit();
        self.allocator.destroy(self.font);
    }
};
