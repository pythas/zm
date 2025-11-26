const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");

const World = @import("world.zig").World;
const Map = @import("map.zig").Map;
const KeyboardState = @import("input.zig").KeyboardState;
const Renderer = @import("renderer/renderer.zig").Renderer;
const SpriteRenderer = @import("renderer/sprite_renderer.zig").SpriteRenderer;
const SpriteRenderData = @import("renderer/sprite_renderer.zig").SpriteRenderData;
const UiRect = @import("renderer/ui_renderer.zig").UiRect;
const tilemapWidth = @import("tile.zig").tilemapWidth;
const tilemapHeight = @import("tile.zig").tilemapHeight;
const scrollCallback = @import("world.zig").scrollCallback;

pub const GameMode = enum {
    InWorld,
    ShipEditor,
};

pub const Game = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    window: *zglfw.Window,
    renderer: Renderer,
    keyboard_state: KeyboardState,
    mode: GameMode = .InWorld,
    world: World,

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        window: *zglfw.Window,
        map: Map,
    ) !Self {
        const world = try World.init(allocator, map);
        const renderer = try Renderer.init(allocator, gctx, window);

        var self = Self{
            .allocator = allocator,
            .window = window,
            .renderer = renderer,
            .world = world,
            .keyboard_state = KeyboardState.init(window),
        };

        for (self.world.map.chunks.items) |*chunk| {
            try self.renderer.world.createChunkRenderData(chunk);
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.world.deinit();
    }

    pub fn setupCallbacks(self: *Self) void {
        self.window.setUserPointer(&self.world);
        _ = self.window.setScrollCallback(scrollCallback);
    }

    pub fn update(self: *Self, dt: f32, t: f32) !void {
        self.keyboard_state.beginFrame();

        if (self.keyboard_state.isPressed(.o)) {
            if (self.mode == .InWorld) {
                self.mode = .ShipEditor;
            } else {
                self.mode = .InWorld;
            }
        }

        switch (self.mode) {
            .InWorld => {
                self.renderer.global.write(self.window, &self.world, dt, t, self.mode, 0.0, 0.0);

                try self.world.update(dt, &self.keyboard_state, self.window);

                if (self.world.map.is_dirty) {
                    // TODO: only for dirty chunks
                    for (self.world.map.chunks.items) |*chunk| {
                        try self.renderer.world.createChunkRenderData(chunk);
                    }

                    self.world.map.is_dirty = false;
                }
            },
            .ShipEditor => {
                const wh = self.window.getFramebufferSize();
                const screen_w: f32 = @floatFromInt(wh[0]);
                const screen_h: f32 = @floatFromInt(wh[1]);

                const mouse_pos = self.window.getCursorPos();
                const mouse_x: f32 = @floatCast(mouse_pos[0]);
                const mouse_y: f32 = @floatCast(mouse_pos[1]);

                const layout = EditorLayout.compute(screen_w, screen_h);

                var hover_x: i32 = -1;
                var hover_y: i32 = -1;

                if (layout.getHoveredTile(mouse_x, mouse_y)) |tile_pos| {
                    hover_x = tile_pos.x;
                    hover_y = tile_pos.y;

                    if (self.window.getMouseButton(.left) == .press) {
                        std.debug.print("DANK", .{});
                        // self.world.player.tiles.set(
                        //     hover_x,
                        //     hover_y,
                        //     selected_tile,
                        // );
                    }
                }

                self.renderer.global.write(
                    self.window,
                    &self.world,
                    dt,
                    t,
                    self.mode,
                    hover_x,
                    hover_y,
                );
            },
        }
    }

    pub fn render(
        self: *Self,
        pass: zgpu.wgpu.RenderPassEncoder,
    ) !void {
        switch (self.mode) {
            .InWorld => {
                const global = &self.renderer.global;
                const world = &self.world;

                try self.renderer.world.writeTextures(world);
                self.renderer.world.draw(pass, global, world);

                const instances = [_]SpriteRenderData{
                    SpriteRenderer.buildPlayerInstance(world),
                };
                try self.renderer.sprite.writeInstances(&instances);
                try self.renderer.sprite.writeTilemap(world.player.tiles);
                self.renderer.sprite.draw(pass, global);

                const beam_instance_count = try self.renderer.beam.writeBuffers(world);
                self.renderer.beam.draw(pass, global, beam_instance_count);
            },
            .ShipEditor => {
                const wh = self.window.getFramebufferSize();
                const screen_w: f32 = @floatFromInt(wh[0]);
                const screen_h: f32 = @floatFromInt(wh[1]);

                const layout = EditorLayout.compute(screen_w, screen_h);

                const mouse_pos = self.window.getCursorPos();
                const mouse_x: f32 = @floatCast(mouse_pos[0]);
                const mouse_y: f32 = @floatCast(mouse_pos[1]);
                const left_mouse_action = self.window.getMouseButton(.left);

                var ui = &self.renderer.ui;
                ui.beginFrame(.{ .x = mouse_x, .y = mouse_y }, left_mouse_action);

                // Background
                try ui.panel(.{ .x = 0, .y = 0, .w = screen_w, .h = screen_h });

                // Palette
                try ui.panel(layout.palette_rect);

                if (try ui.button(.{ .x = layout.palette_rect.x + 10, .y = layout.palette_rect.y + 10, .w = 30, .h = 30 }, "Hull")) {
                    std.debug.print("HULL\n", .{});
                }

                // Ship
                try ui.panel(layout.ship_panel_rect);

                ui.endFrame(pass, &self.renderer.global);

                // Grid sprites
                const global = &self.renderer.global;
                const world = &self.world;

                const instances = [_]SpriteRenderData{
                    .{
                        .wh = .{ tilemapWidth, tilemapHeight, 0, 0 },
                        .position = .{ layout.grid_rect.x + layout.grid_rect.w / 2, layout.grid_rect.y + layout.grid_rect.h / 2, 0, 0 },
                        .rotation = .{ 0, 0, 0, 0 },
                        .scale = layout.scale,
                    },
                };

                try self.renderer.sprite.writeInstances(&instances);
                try self.renderer.sprite.writeTilemap(world.player.tiles);
                self.renderer.sprite.draw(pass, global);
            },
        }
    }
};

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
