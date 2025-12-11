const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");

const MouseState = @import("input.zig").MouseState;
const KeyboardState = @import("input.zig").KeyboardState;
const World = @import("world.zig").World;
const Renderer = @import("renderer/renderer.zig").Renderer;
const SpriteRenderData = @import("renderer/sprite_renderer.zig").SpriteRenderData;
const UiRect = @import("renderer/ui_renderer.zig").UiRect;
const Tile = @import("tile.zig").Tile;
const Direction = @import("tile.zig").Direction;
const Directions = @import("tile.zig").Directions;
const SpriteRenderer = @import("renderer/sprite_renderer.zig").SpriteRenderer;
const TileObject = @import("tile_object.zig").TileObject;
const ship_serialization = @import("ship_serialization.zig");

const tilemapWidth = @import("tile.zig").tilemapWidth;
const tilemapHeight = @import("tile.zig").tilemapHeight;

const EditorLayout = struct {
    const scaling: f32 = 3.0;
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

        const pal_w = (tile_size_base * tilemapWidth * scaling) + (padding * 2);
        const pal_h = header_height;
        const pal_rect = UiRect{ .x = padding, .y = padding, .w = pal_w, .h = pal_h };

        const ship_w = (tile_size_base * tilemapWidth * scaling) + (padding * 2);
        const ship_h = (tile_size_base * tilemapWidth * scaling) + (padding * 2);
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
    Engine,
    RCS,
    Laser,
};

pub const Editor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    window: *zglfw.Window,
    mouse: MouseState,
    keyboard: KeyboardState,
    current_palette: EditorPalette,

    pub fn init(allocator: std.mem.Allocator, window: *zglfw.Window) Self {
        return .{
            .allocator = allocator,
            .window = window,
            .mouse = MouseState.init(window),
            .keyboard = KeyboardState.init(window),
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
        self.keyboard.update();

        if (self.keyboard.isDown(.left_ctrl)) {
            if (self.keyboard.isPressed(.s)) {
                ship_serialization.saveShip(self.allocator, world.objects.items[0], "ship.json") catch |err| {
                    std.debug.print("Failed to save ship: {}\n", .{err});
                };
            }
        }

        const layout = EditorLayout.compute(screen_w, screen_h);

        var hover_x: i32 = -1;
        var hover_y: i32 = -1;

        if (layout.getHoveredTile(self.mouse.x, self.mouse.y)) |tile_pos| {
            hover_x = tile_pos.x;
            hover_y = tile_pos.y;

            const tile_x: usize = @intCast(hover_x);
            const tile_y: usize = @intCast(hover_y);

            // TODO: Make sure tile is connected

            if (self.keyboard.isPressed(.r)) {
                const tile = world.objects.items[0].getTile(tile_x, tile_y);

                if (tile) |ti| {
                    if (ti.category == .Engine) {
                        var t2 = ti;
                        t2.rotation = @enumFromInt((@intFromEnum(t2.rotation) + 1) % 4);
                        t2.sprite = (t2.sprite - 64 + 1) % 4 + 64;
                        world.objects.items[0].setTile(tile_x, tile_y, t2);
                    }
                }
            }

            if (self.mouse.is_left_down) {
                switch (self.current_palette) {
                    .Hull => {
                        const ht = try Tile.init(self.allocator, .Hull, .Metal, .Ships, 36);

                        world.objects.items[0].setTile(tile_x, tile_y, ht);
                    },
                    .Engine => {
                        var engine_dir: ?Direction = null;
                        var is_connected = false;

                        for (Directions) |d| {
                            const n = world.objects.items[0].getNeighbouringTile(
                                tile_x,
                                tile_y,
                                d.direction,
                            ) orelse continue;

                            if (n.category == .Empty) {
                                if (engine_dir == null) {
                                    engine_dir = d.direction;
                                }
                            } else {
                                is_connected = true;
                            }
                        }

                        if (is_connected) {
                            if (engine_dir) |ed| {
                                var et = try Tile.init(self.allocator, .Engine, .Metal, .Ships, switch (ed) {
                                    .North => 64,
                                    .East => 65,
                                    .South => 66,
                                    .West => 67,
                                });
                                et.rotation = ed;

                                world.objects.items[0].setTile(tile_x, tile_y, et);
                            }
                        }
                    },
                    .RCS => {
                        var engine_dir: ?Direction = null;
                        var is_connected = false;

                        for (Directions) |d| {
                            const n = world.objects.items[0].getNeighbouringTile(
                                tile_x,
                                tile_y,
                                d.direction,
                            ) orelse continue;

                            if (n.category == .Empty) {
                                if (engine_dir == null) {
                                    engine_dir = d.direction;
                                }
                            } else {
                                is_connected = true;
                            }
                        }

                        if (is_connected) {
                            if (engine_dir) |ed| {
                                var et = try Tile.init(self.allocator, .RCS, .Metal, .Ships, switch (ed) {
                                    .North => 96,
                                    .East => 97,
                                    .South => 99,
                                    .West => 99,
                                });
                                et.rotation = ed;

                                world.objects.items[0].setTile(tile_x, tile_y, et);
                            }
                        }
                    },
                    .Laser => {},
                }
            }

            if (self.mouse.is_right_down) {
                world.objects.items[0].setTile(tile_x, tile_y, try Tile.initEmpty(self.allocator));
            }
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

        // background
        try ui.panel(.{ .x = 0, .y = 0, .w = screen_w, .h = screen_h });

        // palette
        try ui.panel(layout.palette_rect);

        var btn_x = layout.palette_rect.x + 10;
        const btn_y = layout.palette_rect.y + 10;
        const btn_s = 30;

        if (try ui.button(
            .{ .x = btn_x, .y = btn_y, .w = btn_s, .h = btn_s },
            self.current_palette == .Hull,
            "Hull",
        )) {
            self.current_palette = .Hull;
        }

        btn_x += btn_s + 10;
        if (try ui.button(
            .{ .x = btn_x, .y = btn_y, .w = btn_s, .h = btn_s },
            self.current_palette == .Engine,
            "Engine",
        )) {
            self.current_palette = .Engine;
        }

        btn_x += btn_s + 10;
        if (try ui.button(
            .{ .x = btn_x, .y = btn_y, .w = btn_s, .h = btn_s },
            self.current_palette == .RCS,
            "RCS",
        )) {
            self.current_palette = .RCS;
        }

        // ship
        try ui.panel(layout.ship_panel_rect);

        ui.endFrame(pass, &renderer.global);

        // grid sprites
        const obj = &world.objects.items[0];

        try renderer.sprite.prepareObject(obj);

        const instances = [_]SpriteRenderData{
            .{
                .wh = .{ @floatFromInt(obj.width * 8), @floatFromInt(obj.height * 8), 0, 0 },
                .position = .{ layout.grid_rect.x + layout.grid_rect.w / 2, layout.grid_rect.y + layout.grid_rect.h / 2, 0, 0 },
                .rotation = .{ 0, 0, 0, 0 },
                .scale = layout.scale,
            },
        };
        try renderer.sprite.writeInstances(&instances);

        renderer.sprite.draw(pass, &renderer.global, world.objects.items[0..1]);
    }
};
