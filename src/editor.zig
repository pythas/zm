const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");

const MouseState = @import("input.zig").MouseState;
const World = @import("world.zig").World;
const Renderer = @import("renderer/renderer.zig").Renderer;
const SpriteRenderData = @import("renderer/sprite_renderer.zig").SpriteRenderData;
const UiRect = @import("renderer/ui_renderer.zig").UiRect;

const tilemapWidth = @import("tile.zig").tilemapWidth;
const tilemapHeight = @import("tile.zig").tilemapHeight;

const EditorLayout = struct {
    const scaling: f32 = 4.0;
    const padding: f32 = 10.0;
    const tile_size_base: f32 = 8.0;
    const header_height: f32 = 50.0;

    scale: f32,
    tile_size: f32,

    palette_rect: UiRect,
    ship_panel_rect: UiRect,

    grid_rect: UiRect,

    pub fn compute(screen_w: f32, screen_h: f32) EditorLayout {
        _ = screen_w;
        _ = screen_h;

        const tile_size = tile_size_base * scaling;

        const pal_w = (tile_size_base * 8 * scaling) + (padding * 2);
        const pal_h = header_height;
        const pal_rect = UiRect{ .x = padding, .y = padding, .w = pal_w, .h = pal_h };

        const ship_w = (tile_size_base * 8 * scaling) + (padding * 2);
        const ship_h = (tile_size_base * 8 * scaling) + (padding * 2);
        const ship_y = pal_rect.y + pal_rect.h + padding;
        const ship_rect = UiRect{ .x = padding, .y = ship_y, .w = ship_w, .h = ship_h };

        const grid_w = tile_size * tilemapWidth;
        const grid_h = tile_size * tilemapHeight;
        const grid_rect = UiRect{ .x = ship_rect.x + padding, .y = ship_rect.y + padding, .w = grid_w, .h = grid_h };

        return .{
            .scale = scaling,
            .tile_size = tile_size,
            .palette_rect = pal_rect,
            .ship_panel_rect = ship_rect,
            .grid_rect = grid_rect,
        };
    }

    pub fn getHoveredTile(self: EditorLayout, mouse_x: f32, mouse_y: f32) ?struct { x: i32, y: i32 } {
        if (mouse_x >= self.grid_rect.x and mouse_x < self.grid_rect.x + self.grid_rect.w and
            mouse_y >= self.grid_rect.y and mouse_y < self.grid_rect.y + self.grid_rect.h)
        {
            const local_x = mouse_x - self.grid_rect.x;
            const local_y = mouse_y - self.grid_rect.y;
            return .{
                .x = @intFromFloat(local_x / self.tile_size),
                .y = @intFromFloat(local_y / self.tile_size),
            };
        }
        return null;
    }
};

pub const EditorPalette = enum {
    Hull,
};

pub const Editor = struct {
    const Self = @This();

    window: *zglfw.Window,
    mouse: MouseState,
    current_palette: EditorPalette,

    pub fn init(window: *zglfw.Window) Self {
        return .{
            .window = window,
            .mouse = MouseState.init(window),
            .current_palette = .Hull,
        };
    }

    pub fn update(
        self: *Self,
        renderer: *Renderer,
        world: *World,
        dt: f32,
        t: f32,
    ) void {
        const wh = self.window.getFramebufferSize();
        const screen_w: f32 = @floatFromInt(wh[0]);
        const screen_h: f32 = @floatFromInt(wh[1]);

        self.mouse.update();

        const layout = EditorLayout.compute(screen_w, screen_h);

        var hover_x: i32 = -1;
        var hover_y: i32 = -1;

        if (layout.getHoveredTile(self.mouse.x, self.mouse.y)) |tile_pos| {
            hover_x = tile_pos.x;
            hover_y = tile_pos.y;

            // if (self.window.getMouseButton(.left) == .press) {
            //
            //     // self.world.player.tiles.set(
            //     //     hover_x,
            //     //     hover_y,
            //     //     selected_tile,
            //     // );
            // }
        }

        renderer.global.write(
            self.window,
            world,
            dt,
            t,
            .ShipEditor,
            hover_x,
            hover_y,
        );
    }

    pub fn draw(
        self: *Self,
        renderer: *Renderer,
        world: *World,
        pass: zgpu.wgpu.RenderPassEncoder,
    ) !void {
        const wh = self.window.getFramebufferSize();
        const screen_w: f32 = @floatFromInt(wh[0]);
        const screen_h: f32 = @floatFromInt(wh[1]);

        const layout = EditorLayout.compute(screen_w, screen_h);

        var ui = &renderer.ui;
        ui.beginFrame();

        // Background
        try ui.panel(.{ .x = 0, .y = 0, .w = screen_w, .h = screen_h });

        // Palette
        try ui.panel(layout.palette_rect);

        if (try ui.button(.{ .x = layout.palette_rect.x + 10, .y = layout.palette_rect.y + 10, .w = 30, .h = 30 }, "Hull")) {
            std.debug.print("HULL\n", .{});
        }

        // Ship
        try ui.panel(layout.ship_panel_rect);

        ui.endFrame(pass, &renderer.global);

        // Grid sprites
        const instances = [_]SpriteRenderData{
            .{
                .wh = .{ tilemapWidth, tilemapHeight, 0, 0 },
                .position = .{ layout.grid_rect.x + layout.grid_rect.w / 2, layout.grid_rect.y + layout.grid_rect.h / 2, 0, 0 },
                .rotation = .{ 0, 0, 0, 0 },
                .scale = layout.scale,
            },
        };

        try renderer.sprite.writeInstances(&instances);
        try renderer.sprite.writeTilemap(world.player.tiles);
        renderer.sprite.draw(pass, &renderer.global);
    }
};
