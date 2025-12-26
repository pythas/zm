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
const Tool = @import("inventory.zig").Tool;
const Item = @import("inventory.zig").Item;
const Recipe = @import("inventory.zig").Recipe;
const PartStats = @import("ship.zig").PartStats;

const tilemapWidth = @import("tile.zig").tilemapWidth;
const tilemapHeight = @import("tile.zig").tilemapHeight;

const hover_offset_x = 10;
const hover_offset_y = 10;

const EditorLayout = struct {
    const scaling: f32 = 3.0;
    const padding: f32 = 10.0;
    const tile_size_base: f32 = 8.0;
    const header_height: f32 = 50.0;

    scale: f32,
    tile_size: f32,

    ship_panel_rect: UiRect,
    grid_rect: UiRect,
    inventory_rect: UiRect,
    tools_rect: UiRect,
    recipe_rect: UiRect,
    crafting_rect: UiRect,

    pub fn compute(screen_w: f32, screen_h: f32) EditorLayout {
        _ = screen_w;
        _ = screen_h;

        const tile_size = tile_size_base * scaling;

        const ship_w = (tile_size_base * tilemapWidth * scaling) + (padding * 2);
        const ship_h = (tile_size_base * tilemapWidth * scaling) + (padding * 2);
        const ship_y = padding;
        const ship_rect = UiRect{
            .x = padding,
            .y = ship_y,
            .w = ship_w,
            .h = ship_h,
        };

        const grid_w = tile_size * tilemapWidth;
        const grid_h = tile_size * tilemapHeight;
        const grid_rect = UiRect{
            .x = ship_rect.x + padding,
            .y = ship_rect.y + padding,
            .w = grid_w,
            .h = grid_h,
        };

        const inv_w = tile_size_base * scaling * 8;
        const inv_h = tile_size_base * scaling * 8;
        const inv_rect = UiRect{
            .x = ship_rect.x + ship_rect.w + padding,
            .y = padding,
            .w = inv_w,
            .h = inv_h,
        };

        const tools_w = tile_size_base * scaling * 8;
        const tools_h = tile_size_base * scaling * 4;
        const tools_rect = UiRect{
            .x = inv_rect.x + inv_rect.w + padding,
            .y = padding,
            .w = tools_w,
            .h = tools_h,
        };

        const recipe_w = tile_size_base * scaling * 8;
        const recipe_h = tile_size_base * scaling * 4;
        const recipe_rect = UiRect{
            .x = ship_rect.x + ship_rect.w + padding,
            .y = inv_rect.y + inv_rect.h + padding,
            .w = recipe_w,
            .h = recipe_h,
        };

        const crafting_w = tile_size_base * scaling * 8;
        const crafting_h = tile_size_base * scaling * 1;
        const crafting_rect = UiRect{
            .x = recipe_rect.x,
            .y = recipe_rect.y + recipe_rect.h + padding,
            .w = crafting_w,
            .h = crafting_h,
        };

        return .{
            .scale = scaling,
            .tile_size = tile_size,
            .ship_panel_rect = ship_rect,
            .grid_rect = grid_rect,
            .inventory_rect = inv_rect,
            .tools_rect = tools_rect,
            .recipe_rect = recipe_rect,
            .crafting_rect = crafting_rect,
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

pub const Editor = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    window: *zglfw.Window,
    mouse: MouseState,
    keyboard: KeyboardState,
    current_tool: ?Tool = null,
    current_recipe: ?Recipe = null,

    pub fn init(allocator: std.mem.Allocator, window: *zglfw.Window) Self {
        return .{
            .allocator = allocator,
            .window = window,
            .mouse = MouseState.init(window),
            .keyboard = KeyboardState.init(window),
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
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

        const ship = &world.objects.items[0];

        if (self.keyboard.isDown(.left_ctrl)) {
            if (self.keyboard.isPressed(.s)) {
                ship_serialization.saveShip(self.allocator, ship.*, "ship.json") catch |err| {
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
                if (ship.getTile(tile_x, tile_y)) |tile| {
                    if (tile.data == .ship_part and tile.data.ship_part.kind == .chemical_thruster) {
                        var new_tile = tile.*;
                        new_tile.data.ship_part.rotation = @enumFromInt((@intFromEnum(new_tile.data.ship_part.rotation) + 1) % 4);
                        ship.setTile(tile_x, tile_y, new_tile);
                    }
                }
            }

            if (self.mouse.is_left_clicked) {
                if (self.current_tool != null) {
                    switch (self.current_tool.?) {
                        .welding => {
                            if (ship.getTile(tile_x, tile_y)) |tile| {
                                if (tile.data == .ship_part) {
                                    switch (tile.data.ship_part.kind) {
                                        .chemical_thruster => {
                                            const iron = Item{ .resource = .iron };
                                            const count_iron = ship.getInventoryCountByItem(iron);

                                            if (count_iron >= 10) {
                                                var new_tile = tile.*;
                                                new_tile.data.ship_part.health = PartStats.getFunctionalThreshold(new_tile.data.ship_part.kind, new_tile.data.ship_part.tier);
                                                ship.setTile(tile_x, tile_y, new_tile);

                                                ship.removeNumberOfItemsFromInventory(iron, 10);
                                                _ = world.research_manager.reportRepair("broken_chemical_thruster");
                                            }
                                        },
                                        else => {},
                                    }
                                }
                            }
                        },
                    }
                }
            }

            if (self.mouse.is_right_down) {
                ship.setTile(tile_x, tile_y, try Tile.initEmpty());
            }
        }

        renderer.global.write(
            self.window,
            world,
            dt,
            t,
            .ship_editor,
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
        const ship = &world.objects.items[0];

        var ui = &renderer.ui;
        ui.beginFrame();

        // background
        try ui.panel(.{ .x = 0, .y = 0, .w = screen_w, .h = screen_h });

        // hover
        var hovered_item_name: ?[]const u8 = null;
        var hover_pos_x: f32 = 0;
        var hover_pos_y: f32 = 0;

        // ship grid
        try ui.panel(layout.ship_panel_rect);

        try renderer.sprite.prepareObject(ship);
        const instances = [_]SpriteRenderData{
            .{
                .wh = .{ @floatFromInt(ship.width * 8), @floatFromInt(ship.height * 8), 0, 0 },
                .position = .{ layout.grid_rect.x + layout.grid_rect.w / 2, layout.grid_rect.y + layout.grid_rect.h / 2, 0, 0 },
                .rotation = .{ 0, 0, 0, 0 },
                .scale = layout.scale,
            },
        };
        try renderer.sprite.writeInstances(&instances);

        if (layout.getHoveredTile(self.mouse.x, self.mouse.y)) |tile_pos| {
            const tile_x: usize = @intCast(tile_pos.x);
            const tile_y: usize = @intCast(tile_pos.y);

            if (ship.getTile(tile_x, tile_y)) |tile| {
                if (tile.getShipPart()) |ship_part| {
                    const name = PartStats.getName(ship_part.kind);
                    var prefix: []const u8 = "";
                    var extra: []const u8 = "";

                    if (PartStats.isBroken(ship_part)) {
                        prefix = "Broken ";

                        if (self.current_tool) |t| {
                            if (t == .welding) {
                                extra = "\nRepair: 10 iron";
                            }
                        }
                    }

                    var buf: [255]u8 = undefined;
                    const text = std.fmt.bufPrint(&buf, "{s}{s}{s}", .{ prefix, name, extra }) catch "!";

                    hovered_item_name = text;
                    hover_pos_x = self.mouse.x + hover_offset_x;
                    hover_pos_y = self.mouse.y + hover_offset_y;
                }
            }
        }

        // inventory
        try ui.panel(layout.inventory_rect);

        const slot_size: f32 = 20.0;
        const slot_padding: f32 = 2.0;

        var inv_x = layout.inventory_rect.x + 10;
        var inv_y = layout.inventory_rect.y + 10;

        var inv_it = ship.inventories.valueIterator();
        while (inv_it.next()) |inv| {
            for (inv.stacks.items) |stack| {
                const slot_rect = UiRect{ .x = inv_x, .y = inv_y, .w = slot_size, .h = slot_size };

                if (slot_rect.contains(.{ .x = self.mouse.x, .y = self.mouse.y })) {
                    if (stack.item != .none) {
                        hovered_item_name = stack.item.getName();
                        hover_pos_x = self.mouse.x + hover_offset_x;
                        hover_pos_y = self.mouse.y + hover_offset_y;
                    }
                }

                _ = try ui.inventorySlot(slot_rect, stack.item, stack.amount, false, renderer.font);

                inv_x += slot_size + slot_padding;
                if (inv_x + slot_size > layout.inventory_rect.x + layout.inventory_rect.w) {
                    inv_x = layout.inventory_rect.x + 10;
                    inv_y += slot_size + slot_padding;
                }

                if (inv_y + slot_size > layout.inventory_rect.y + layout.inventory_rect.h) {
                    break;
                }
            }
        }

        // tools
        try ui.panel(layout.tools_rect);

        var tool_x = layout.tools_rect.x + 10;
        const tool_y = layout.tools_rect.y + 10;

        if (world.research_manager.isUnlocked(.welding)) {
            const tool_rect = UiRect{ .x = tool_x, .y = tool_y, .w = slot_size, .h = slot_size };
            const item = Item{ .tool = .welding };

            var is_selected = false;
            if (self.current_tool) |t| {
                if (t == .welding) is_selected = true;
            }

            if (tool_rect.contains(.{ .x = self.mouse.x, .y = self.mouse.y })) {
                hovered_item_name = item.getName();
                hover_pos_x = self.mouse.x + hover_offset_x;
                hover_pos_y = self.mouse.y + hover_offset_y;
            }

            if (try ui.toolSlot(tool_rect, item, is_selected)) {
                self.current_tool = if (is_selected) null else .welding;
            }
            tool_x += slot_size + slot_padding;
        }

        // crafting
        try ui.panel(layout.recipe_rect);

        var recipe_x = layout.recipe_rect.x + 10;
        const recipe_y = layout.recipe_rect.y + 10;

        if (world.research_manager.isUnlocked(.chemical_thruster)) {
            const recipe_rect = UiRect{ .x = recipe_x, .y = recipe_y, .w = slot_size, .h = slot_size };
            const item = Item{ .recipe = .chemical_thruster };

            var is_selected = false;
            if (self.current_recipe) |r| {
                if (r == .chemical_thruster) is_selected = true;
            }

            if (recipe_rect.contains(.{ .x = self.mouse.x, .y = self.mouse.y })) {
                hovered_item_name = item.getName();
                hover_pos_x = self.mouse.x + hover_offset_x;
                hover_pos_y = self.mouse.y + hover_offset_y;
            }

            if (try ui.recipeSlot(recipe_rect, item, is_selected)) {
                self.current_recipe = if (is_selected) null else .chemical_thruster;
            }

            recipe_x += slot_size + slot_padding;
        }

        if (try ui.button(
            layout.crafting_rect,
            false,
            self.current_recipe == null,
            "Construct",
            renderer.font,
        )) {
            // TODO: add crafting delay
            _ = try ship.addItemToInventory(
                .{ .component = .chemical_thruster },
                1,
                ship.position,
            );

            // TODO: report
        }

        ui.flush(pass, &renderer.global);

        renderer.sprite.draw(pass, &renderer.global, world.objects.items[0..1]);

        // tooltips
        if (hovered_item_name) |name| {
            try ui.tooltip(hover_pos_x, hover_pos_y, name, renderer.font);
            ui.flush(pass, &renderer.global);
        }
    }
};
