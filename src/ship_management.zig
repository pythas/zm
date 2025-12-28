const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");

const MouseState = @import("input.zig").MouseState;
const KeyboardState = @import("input.zig").KeyboardState;
const World = @import("world.zig").World;
const Renderer = @import("renderer.zig").Renderer;
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
const Stack = @import("inventory.zig").Stack;
const Recipe = @import("inventory.zig").Recipe;
const RecipeStats = @import("inventory.zig").RecipeStats;
const PartStats = @import("ship.zig").PartStats;
const ShipManagementLayout = @import("ship_management/layout.zig").ShipManagementLayout;

const tilemapWidth = @import("tile.zig").tilemapWidth;
const tilemapHeight = @import("tile.zig").tilemapHeight;

const hover_offset_x = 10;
const hover_offset_y = 10;

pub const ShipManagement = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    window: *zglfw.Window,
    mouse: MouseState,
    keyboard: KeyboardState,
    current_tool: ?Tool = null,
    current_recipe: ?Recipe = null,

    cursor_item: Stack = .{},

    hovered_item_name: ?[]const u8 = null,
    hover_text_buf: [255]u8 = undefined,
    hover_pos_x: f32 = 0,
    hover_pos_y: f32 = 0,

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
        const layout = ShipManagementLayout.compute(screen_w, screen_h);

        self.handleShortcuts(ship);

        var hover_x: i32 = -1;
        var hover_y: i32 = -1;

        if (layout.getHoveredTile(self.mouse.x, self.mouse.y)) |tile_pos| {
            hover_x = tile_pos.x;
            hover_y = tile_pos.y;

            self.handleTileInteraction(ship, tile_pos.x, tile_pos.y, world);
        }

        renderer.global.write(
            self.window,
            world,
            dt,
            t,
            .ship_management,
            hover_x,
            hover_y,
        );
    }

    pub fn save(self: *ShipManagement, ship: *TileObject) void {
        ship_serialization.saveShip(self.allocator, ship.*, "assets/ship.json") catch |err| {
            std.debug.print("Failed to save ship: {}\n", .{err});
        };
    }

    fn handleShortcuts(self: *Self, ship: *TileObject) void {
        if (self.keyboard.isDown(.left_ctrl) and self.keyboard.isPressed(.s)) {
            self.save(ship);
        }
    }

    fn handleTileInteraction(self: *Self, ship: *TileObject, hover_x: i32, hover_y: i32, world: *World) void {
        const tile_x: usize = @intCast(hover_x);
        const tile_y: usize = @intCast(hover_y);

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
            if (self.current_tool) |tool| {
                switch (tool) {
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
            } else {
                switch (self.cursor_item.item) {
                    .component => |part_kind| {
                        if (ship.getTile(tile_x, tile_y)) |tile| {
                            if (tile.data == .empty) {
                                const tier = 1; // Default tier
                                const health = PartStats.getMaxHealth(part_kind, tier);
                                const new_tile = Tile.init(.{
                                    .ship_part = .{
                                        .kind = part_kind,
                                        .tier = tier,
                                        .health = health,
                                        .rotation = .north,
                                    },
                                }) catch unreachable;

                                ship.setTile(tile_x, tile_y, new_tile);

                                self.cursor_item.amount -= 1;
                                if (self.cursor_item.amount == 0) {
                                    self.cursor_item = .{};
                                }
                            }
                        }
                    },
                    else => {},
                }
            }
        }

        if (self.mouse.is_right_down) {
            ship.setTile(tile_x, tile_y, Tile.initEmpty() catch unreachable);
        }
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

        const layout = ShipManagementLayout.compute(screen_w, screen_h);
        const ship = &world.objects.items[0];

        // reset hover state
        self.hovered_item_name = null;

        var ui = &renderer.ui;
        ui.beginFrame();

        // background
        try ui.panel(.{ .x = 0, .y = 0, .w = screen_w, .h = screen_h });

        try self.drawShipPanel(renderer, layout, ship);
        try self.drawInventoryPanel(renderer, layout, ship);
        try self.drawToolsPanel(renderer, layout, world);
        try self.drawRecipesPanel(renderer, layout, world);
        try self.drawCraftingPanel(renderer, layout, ship);

        ui.flush(pass, &renderer.global);
        renderer.sprite.draw(pass, &renderer.global, world.objects.items[0..1]);

        // tooltips
        if (self.hovered_item_name) |name| {
            try ui.tooltip(self.hover_pos_x, self.hover_pos_y, name, renderer.font);
            ui.flush(pass, &renderer.global);
        }

        if (self.cursor_item.item != .none) {
            const slot_size: f32 = 20.0;
            const cursor_rect = UiRect{
                .x = self.mouse.x - slot_size / 2,
                .y = self.mouse.y - slot_size / 2,
                .w = slot_size,
                .h = slot_size,
            };
            _ = try ui.inventorySlot(cursor_rect, self.cursor_item.item, self.cursor_item.amount, true, renderer.font);
            ui.flush(pass, &renderer.global);
        }
    }

    fn drawShipPanel(self: *Self, renderer: *Renderer, layout: ShipManagementLayout, ship: *TileObject) !void {
        var ui = &renderer.ui;
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

                    const text = std.fmt.bufPrint(&self.hover_text_buf, "{s}{s}{s}", .{ prefix, name, extra }) catch "!";

                    self.hovered_item_name = text;
                    self.hover_pos_x = self.mouse.x + hover_offset_x;
                    self.hover_pos_y = self.mouse.y + hover_offset_y;
                }
            }
        }
    }

    fn drawInventoryPanel(self: *Self, renderer: *Renderer, layout: ShipManagementLayout, ship: *TileObject) !void {
        var ui = &renderer.ui;
        try ui.panel(layout.inventory_rect);

        const slot_size: f32 = 20.0;
        const slot_padding: f32 = 2.0;

        var inv_x = layout.inventory_rect.x + 10;
        var inv_y = layout.inventory_rect.y + 10;

        var inv_it = ship.inventories.valueIterator();
        while (inv_it.next()) |inv| {
            for (inv.stacks.items) |*stack| {
                const slot_rect = UiRect{ .x = inv_x, .y = inv_y, .w = slot_size, .h = slot_size };

                if (slot_rect.contains(.{ .x = self.mouse.x, .y = self.mouse.y })) {
                    if (stack.item != .none) {
                        self.hovered_item_name = stack.item.getName();
                        self.hover_pos_x = self.mouse.x + hover_offset_x;
                        self.hover_pos_y = self.mouse.y + hover_offset_y;
                    }
                }

                const state = try ui.inventorySlot(slot_rect, stack.item, stack.amount, false, renderer.font);

                if (state.is_clicked) {
                    if (self.cursor_item.item == .none) {
                        if (stack.item != .none) {
                            self.cursor_item = stack.*;
                            stack.* = .{};
                        }
                    } else {
                        if (stack.item == .none) {
                            stack.* = self.cursor_item;
                            self.cursor_item = .{};
                        } else if (stack.item.eql(self.cursor_item.item)) {
                            const max = stack.item.getMaxStack();
                            const available = max - stack.amount;
                            const take = @min(available, self.cursor_item.amount);
                            stack.amount += take;
                            self.cursor_item.amount -= take;
                            if (self.cursor_item.amount == 0) self.cursor_item = .{};
                        } else {
                            const temp = stack.*;
                            stack.* = self.cursor_item;
                            self.cursor_item = temp;
                        }
                    }
                } else if (state.is_right_clicked) {
                    if (self.cursor_item.item == .none) {
                        if (stack.item != .none and stack.amount > 0) {
                            // take 1
                            if (self.cursor_item.item == .none) {
                                self.cursor_item = .{ .item = stack.item, .amount = 0 };
                            }
                            // assuming we only support taking into empty cursor for now or matching

                            self.cursor_item.amount += 1;
                            stack.amount -= 1;
                            if (stack.amount == 0) stack.item = .none;
                        }
                    } else {
                        // place 1
                        if (stack.item == .none) {
                            stack.item = self.cursor_item.item;
                            stack.amount = 1;
                            self.cursor_item.amount -= 1;
                            if (self.cursor_item.amount == 0) self.cursor_item = .{};
                        } else if (stack.item.eql(self.cursor_item.item)) {
                            if (stack.amount < stack.item.getMaxStack()) {
                                stack.amount += 1;
                                self.cursor_item.amount -= 1;
                                if (self.cursor_item.amount == 0) self.cursor_item = .{};
                            }
                        } else {
                            const temp = stack.*;
                            stack.* = self.cursor_item;
                            self.cursor_item = temp;
                        }
                    }
                }

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
    }

    fn drawToolsPanel(self: *Self, renderer: *Renderer, layout: ShipManagementLayout, world: *World) !void {
        var ui = &renderer.ui;
        try ui.panel(layout.tools_rect);

        if (self.mouse.is_left_clicked and layout.tools_rect.contains(.{ .x = self.mouse.x, .y = self.mouse.y })) {
            self.current_recipe = null;
        }

        const slot_size: f32 = 20.0;
        const slot_padding: f32 = 2.0;

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
                self.hovered_item_name = item.getName();
                self.hover_pos_x = self.mouse.x + hover_offset_x;
                self.hover_pos_y = self.mouse.y + hover_offset_y;
            }

            if ((try ui.toolSlot(tool_rect, item, is_selected)).is_clicked) {
                self.current_tool = if (is_selected) null else .welding;
            }
            tool_x += slot_size + slot_padding;
        }
    }

    fn drawRecipesPanel(self: *Self, renderer: *Renderer, layout: ShipManagementLayout, world: *World) !void {
        var ui = &renderer.ui;
        try ui.panel(layout.recipe_rect);

        if (self.mouse.is_left_clicked and layout.recipe_rect.contains(.{ .x = self.mouse.x, .y = self.mouse.y })) {
            self.current_tool = null;
        }

        const slot_size: f32 = 20.0;
        const slot_padding: f32 = 2.0;

        var recipe_x = layout.recipe_rect.x + 10;
        const recipe_y = layout.recipe_rect.y + 10;

        for (std.enums.values(Recipe)) |recipe| {
            if (world.research_manager.isUnlocked(RecipeStats.getResearchId(recipe))) {
                const recipe_rect = UiRect{ .x = recipe_x, .y = recipe_y, .w = slot_size, .h = slot_size };
                const item = Item{ .recipe = recipe };

                var is_selected = false;
                if (self.current_recipe) |r| {
                    if (r == recipe) is_selected = true;
                }

                if (recipe_rect.contains(.{ .x = self.mouse.x, .y = self.mouse.y })) {
                    self.hovered_item_name = item.getName();
                    self.hover_pos_x = self.mouse.x + hover_offset_x;
                    self.hover_pos_y = self.mouse.y + hover_offset_y;
                }

                if ((try ui.recipeSlot(recipe_rect, item, is_selected)).is_clicked) {
                    self.current_recipe = if (is_selected) null else recipe;
                }

                recipe_x += slot_size + slot_padding;
            }
        }
    }

    fn tryCraft(self: *Self, ship: *TileObject, recipe: Recipe) !void {
        _ = self;
        const costs = RecipeStats.getCost(recipe);

        for (costs) |cost| {
            const count = ship.getInventoryCountByItem(cost.item);

            if (count < cost.amount) {
                return;
            }
        }

        for (costs) |cost| {
            ship.removeNumberOfItemsFromInventory(cost.item, cost.amount);
        }

        const result = RecipeStats.getResult(recipe);
        const remaining = try ship.addItemToInventory(
            result,
            1,
            ship.position,
        );

        if (remaining == 0) {
            std.log.info("ShipManagement: Constructed {s}", .{RecipeStats.getName(recipe)});
        } else {
            std.log.warn("ShipManagement: Failed to add {s} to inventory (no space?)", .{RecipeStats.getName(recipe)});
        }
    }

    fn drawCraftingPanel(self: *Self, renderer: *Renderer, layout: ShipManagementLayout, ship: *TileObject) !void {
        var ui = &renderer.ui;
        const button_state = try ui.button(
            layout.crafting_rect,
            false,
            self.current_recipe == null,
            "Construct",
            renderer.font,
        );
        if (button_state.is_clicked) {
            if (self.current_recipe) |recipe| {
                try self.tryCraft(ship, recipe);
            }
        }
    }
};
