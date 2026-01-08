const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");

const InputManager = @import("../input/input_manager.zig").InputManager;
const World = @import("../world.zig").World;
const Renderer = @import("../renderer.zig").Renderer;
const SpriteRenderData = @import("../renderer/sprite_renderer.zig").SpriteRenderData;
const UiRect = @import("../renderer/ui_renderer.zig").UiRect;
const Tile = @import("../tile.zig").Tile;
const TileObject = @import("../tile_object.zig").TileObject;
const Stack = @import("../inventory.zig").Stack;
const Recipe = @import("../inventory.zig").Recipe;
const RecipeStats = @import("../inventory.zig").RecipeStats;
const PartStats = @import("../ship.zig").PartStats;
const ShipManagementLayout = @import("../ship_management/layout.zig").ShipManagementLayout;
const DropdownItem = @import("../renderer/ui_renderer.zig").UiRenderer.DropdownItem;
const ShipLogic = @import("../systems/ship_logic.zig").ShipLogic;
const Item = @import("../inventory.zig").Item;

const hover_offset_x = 10;
const hover_offset_y = 10;

pub const ShipManagementUi = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    window: *zglfw.Window,

    logic: ShipLogic,

    current_recipe: ?Recipe = null,
    cursor_item: Stack = .{},

    hovered_item_name: ?[]const u8 = null,
    hover_text_buf: [255]u8 = undefined,
    hover_pos_x: f32 = 0,
    hover_pos_y: f32 = 0,

    is_tile_menu_open: bool = false,
    tile_menu_x: f32 = 0,
    tile_menu_y: f32 = 0,
    tile_menu_tile_x: usize = 0,
    tile_menu_tile_y: usize = 0,

    pub fn init(allocator: std.mem.Allocator, window: *zglfw.Window) Self {
        return .{
            .allocator = allocator,
            .window = window,
            .logic = .{},
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn updateCrafting(self: *Self, dt: f32, world: *World) !void {
        const ship = &world.objects.items[0];
        try self.logic.updateCrafting(dt, world, ship);
    }

    pub fn update(
        self: *Self,
        renderer: *Renderer,
        world: *World,
        input: *const InputManager,
        dt: f32,
        t: f32,
    ) !void {
        const wh = self.window.getFramebufferSize();
        const screen_w: f32 = @floatFromInt(wh[0]);
        const screen_h: f32 = @floatFromInt(wh[1]);

        const ship = &world.objects.items[0];

        try self.updateCrafting(dt, world);

        const layout = ShipManagementLayout.compute(screen_w, screen_h, renderer.ui.style);

        self.handleShortcuts(ship, input);

        var hover_x: i32 = -1;
        var hover_y: i32 = -1;

        if (!self.is_tile_menu_open) {
            if (layout.getHoveredTile(input.mouse.x, input.mouse.y)) |tile_pos| {
                hover_x = tile_pos.x;
                hover_y = tile_pos.y;

                try self.handleTileInteraction(ship, tile_pos.x, tile_pos.y, world, input);
            }
        }

        renderer.global.write(
            self.window,
            world,
            dt,
            t,
            .ship_management,
        );
    }

    fn handleShortcuts(self: *Self, ship: *TileObject, input: *const InputManager) void {
        if (input.keyboard.isDown(.left_ctrl) and input.keyboard.isPressed(.s)) {
            ShipLogic.save(self.allocator, ship);
        }
    }

    fn handleTileInteraction(self: *Self, ship: *TileObject, hover_x: i32, hover_y: i32, world: *World, input: *const InputManager) !void {
        _ = world;
        const tile_x: usize = @intCast(hover_x);
        const tile_y: usize = @intCast(hover_y);

        if (input.keyboard.isPressed(.r)) {
            ShipLogic.rotateTile(ship, tile_x, tile_y);
        }

        if (input.mouse.is_left_clicked) {
            switch (self.cursor_item.item) {
                .component => |part_kind| {
                    try ShipLogic.constructPart(ship, tile_x, tile_y, part_kind, &self.cursor_item);
                },
                else => {},
            }
        }
    }

    pub fn draw(
        self: *Self,
        renderer: *Renderer,
        world: *World,
        input: *const InputManager,
        pass: zgpu.wgpu.RenderPassEncoder,
    ) !void {
        const wh = self.window.getFramebufferSize();
        const screen_w: f32 = @floatFromInt(wh[0]);
        const screen_h: f32 = @floatFromInt(wh[1]);

        const layout = ShipManagementLayout.compute(screen_w, screen_h, renderer.ui.style);
        const ship = &world.objects.items[0];

        // reset hover state
        self.hovered_item_name = null;

        var ui = &renderer.ui;
        ui.beginFrame();

        if (self.is_tile_menu_open) {
            ui.setInteractionEnabled(false);
        }

        // background
        _ = try ui.panel(.{ .x = 0, .y = 0, .w = screen_w, .h = screen_h }, null, null);

        try self.drawShipPanel(renderer, layout, ship, input);
        try self.drawInventoryPanel(renderer, layout, ship, input);
        try self.drawToolsPanel(renderer, layout, world, input);
        try self.drawRecipesPanel(renderer, layout, world, input);
        try self.drawCraftingPanel(renderer, layout, ship);

        ui.flush(pass, &renderer.global);
        renderer.sprite.draw(pass, &renderer.global, world.objects.items[0..1]);

        ui.setInteractionEnabled(true);

        // tooltips
        if (self.hovered_item_name) |name| {
            try ui.tooltip(self.hover_pos_x, self.hover_pos_y, name, renderer.font);
            ui.flush(pass, &renderer.global);
        }

        try self.drawTileMenu(renderer, layout, ship, world, input);
        ui.flush(pass, &renderer.global);

        if (self.cursor_item.item != .none) {
            const slot_size = renderer.ui.style.slot_size;
            const cursor_rect = UiRect{
                .x = input.mouse.x - slot_size / 2,
                .y = input.mouse.y - slot_size / 2,
                .w = slot_size,
                .h = slot_size,
            };

            _ = try ui.inventorySlot(cursor_rect, self.cursor_item.item, self.cursor_item.amount, true, renderer.font);
            ui.flush(pass, &renderer.global);
        }

        try world.notifications.draw(ui, screen_w, screen_h, renderer.font);
        ui.flush(pass, &renderer.global);
    }

    fn drawShipPanel(self: *Self, renderer: *Renderer, layout: ShipManagementLayout, ship: *TileObject, input: *const InputManager) !void {
        var ui = &renderer.ui;
        _ = try ui.panel(layout.ship_panel_rect, null, null);

        var hover_x: i32 = -1;
        var hover_y: i32 = -1;
        var hover_active: f32 = 0.0;

        if (layout.getHoveredTile(input.mouse.x, input.mouse.y)) |tile_pos| {
            hover_x = tile_pos.x;
            hover_y = tile_pos.y;
            hover_active = 1.0;
        }

        try renderer.sprite.prepareObject(ship);
        const instances = [_]SpriteRenderData{
            .{
                .wh = .{ @floatFromInt(ship.width * 8), @floatFromInt(ship.height * 8), 0, 0 },
                .position = .{ layout.grid_rect.x + layout.grid_rect.w / 2, layout.grid_rect.y + layout.grid_rect.h / 2, 0, 0 },
                .rotation = .{ 0, 0, 0, 0 },
                .hover = .{ @floatFromInt(hover_x), @floatFromInt(hover_y), hover_active, 0 },
                .scale = layout.scale,
            },
        };
        try renderer.sprite.writeInstances(&instances);

        if (hover_active > 0.5) {
            const tile_x: usize = @intCast(hover_x);
            const tile_y: usize = @intCast(hover_y);

            if (ship.getTile(tile_x, tile_y)) |tile| {
                if (tile.getShipPart()) |ship_part| {
                    const name = PartStats.getName(ship_part.kind);
                    var prefix: []const u8 = "";
                    const extra: []const u8 = "";

                    if (PartStats.isBroken(ship_part)) {
                        prefix = "Broken ";
                    }

                    const text = std.fmt.bufPrint(
                        &self.hover_text_buf,
                        "{s}{s}{s}{s}{d}",
                        .{ prefix, name, extra, "\nHealth: ", ship_part.health },
                    ) catch "!";

                    self.hovered_item_name = text;
                    self.hover_pos_x = input.mouse.x + hover_offset_x;
                    self.hover_pos_y = input.mouse.y + hover_offset_y;
                }
            }
        }
    }

    fn drawInventoryPanel(self: *Self, renderer: *Renderer, layout: ShipManagementLayout, ship: *TileObject, input: *const InputManager) !void {
        var ui = &renderer.ui;
        const content_rect = try ui.panel(layout.inventory_rect, "Inventory", renderer.font);

        const slot_size = renderer.ui.style.slot_size;
        const slot_padding = renderer.ui.style.slot_padding;

        var inv_x = content_rect.x;
        var inv_y = content_rect.y;

        var inv_it = ship.inventories.valueIterator();
        while (inv_it.next()) |inv| {
            for (inv.stacks.items) |*stack| {
                const slot_rect = UiRect{ .x = inv_x, .y = inv_y, .w = slot_size, .h = slot_size };

                if (slot_rect.contains(.{ .x = input.mouse.x, .y = input.mouse.y })) {
                    if (stack.item != .none) {
                        self.hovered_item_name = stack.item.getName();
                        self.hover_pos_x = input.mouse.x + hover_offset_x;
                        self.hover_pos_y = input.mouse.y + hover_offset_y;
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
                if (inv_x + slot_size > content_rect.x + content_rect.w) {
                    inv_x = content_rect.x;
                    inv_y += slot_size + slot_padding;
                }

                if (inv_y + slot_size > content_rect.y + content_rect.h) {
                    break;
                }
            }
        }
    }

    fn drawToolsPanel(self: *Self, renderer: *Renderer, layout: ShipManagementLayout, world: *World, input: *const InputManager) !void {
        var ui = &renderer.ui;
        const content_rect = try ui.panel(layout.tools_rect, "Tools", renderer.font);

        if (input.mouse.is_left_clicked and layout.tools_rect.contains(.{ .x = input.mouse.x, .y = input.mouse.y })) {
            self.current_recipe = null;
        }

        const slot_size = renderer.ui.style.slot_size;
        const slot_padding = renderer.ui.style.slot_padding;

        var tool_x = content_rect.x;
        var tool_y = content_rect.y;

        if (world.research_manager.isUnlocked(.welding)) {
            const tool_rect = UiRect{ .x = tool_x, .y = tool_y, .w = slot_size, .h = slot_size };
            const item = Item{ .tool = .welding };

            if (tool_rect.contains(.{ .x = input.mouse.x, .y = input.mouse.y })) {
                self.hovered_item_name = item.getName();
                self.hover_pos_x = input.mouse.x + hover_offset_x;
                self.hover_pos_y = input.mouse.y + hover_offset_y;
            }

            _ = try ui.toolSlot(tool_rect, item);
            tool_x += slot_size + slot_padding;

            if (tool_x + slot_size > content_rect.x + content_rect.w) {
                tool_x = content_rect.x;
                tool_y += slot_size + slot_padding;
            }
        }
    }

    fn drawRecipesPanel(self: *Self, renderer: *Renderer, layout: ShipManagementLayout, world: *World, input: *const InputManager) !void {
        var ui = &renderer.ui;
        const content_rect = try ui.panel(layout.recipe_rect, "Recipes", renderer.font);

        const slot_size = renderer.ui.style.slot_size;
        const slot_padding = renderer.ui.style.slot_padding;

        var recipe_x = content_rect.x;
        var recipe_y = content_rect.y;

        for (std.enums.values(Recipe)) |recipe| {
            if (world.research_manager.isUnlocked(RecipeStats.getResearchId(recipe))) {
                const recipe_rect = UiRect{ .x = recipe_x, .y = recipe_y, .w = slot_size, .h = slot_size };
                const item = Item{ .recipe = recipe };

                var is_selected = false;
                if (self.current_recipe) |r| {
                    if (r == recipe) is_selected = true;
                }

                if (recipe_rect.contains(.{ .x = input.mouse.x, .y = input.mouse.y })) {
                    self.hovered_item_name = item.getName();
                    self.hover_pos_x = input.mouse.x + hover_offset_x;
                    self.hover_pos_y = input.mouse.y + hover_offset_y;
                }

                if ((try ui.recipeSlot(recipe_rect, item, is_selected)).is_clicked) {
                    self.current_recipe = if (is_selected) null else recipe;
                }

                recipe_x += slot_size + slot_padding;

                if (recipe_x + slot_size > content_rect.x + content_rect.w) {
                    recipe_x = content_rect.x;
                    recipe_y += slot_size + slot_padding;
                }

                if (recipe_y + slot_size > content_rect.y + content_rect.h) {
                    break;
                }
            }
        }
    }

    fn drawCraftingPanel(self: *Self, renderer: *Renderer, layout: ShipManagementLayout, ship: *TileObject) !void {
        var ui = &renderer.ui;

        if (self.logic.active_crafting) |task| {
            // progress bar
            _ = try ui.panel(layout.crafting_rect, null, null);

            const padding = renderer.ui.style.progress_bar_padding;
            const bar_h = renderer.ui.style.progress_bar_height;
            const bar_w = layout.crafting_rect.w - padding * 2.0;
            const bar_x = layout.crafting_rect.x + padding;
            const bar_y = layout.crafting_rect.y + (layout.crafting_rect.h - bar_h) / 2.0;

            // background
            try ui.rectangle(.{ .x = bar_x, .y = bar_y, .w = bar_w, .h = bar_h }, renderer.ui.style.progress_bar_bg_color);

            // foreground
            const progress = task.progress / task.duration;
            const fill_w = bar_w * progress;
            try ui.rectangle(.{ .x = bar_x, .y = bar_y, .w = fill_w, .h = bar_h }, renderer.ui.style.progress_bar_fg_color);

            // text
            var buf: [64]u8 = undefined;
            const text = std.fmt.bufPrint(&buf, "Crafting: {d:.1}s", .{task.duration - task.progress}) catch "Crafting...";
            const text_y = bar_y + (bar_h + renderer.font.ascent) / 2.0;
            try ui.label(.{ .x = bar_x + padding, .y = text_y }, text, renderer.font, renderer.ui.style.progress_bar_text_color);
        } else {
            const button_state = try ui.button(
                layout.crafting_rect,
                false,
                self.current_recipe == null,
                "Construct",
                renderer.font,
            );

            if (button_state.is_clicked) {
                if (self.current_recipe) |recipe| {
                    try self.logic.tryCraft(ship, recipe);
                }
            }
        }
    }

    fn drawTileMenu(self: *Self, renderer: *Renderer, layout: ShipManagementLayout, ship: *TileObject, world: *World, input: *const InputManager) !void {
        if (input.mouse.is_right_clicked) {
            self.is_tile_menu_open = true;
            self.tile_menu_x = input.mouse.x;
            self.tile_menu_y = input.mouse.y;

            if (layout.getHoveredTile(input.mouse.x, input.mouse.y)) |tile_pos| {
                self.tile_menu_tile_x = @intCast(tile_pos.x);
                self.tile_menu_tile_y = @intCast(tile_pos.y);
            }
        }

        if (!self.is_tile_menu_open) {
            return;
        }

        const tile = ship.getTile(self.tile_menu_tile_x, self.tile_menu_tile_y) orelse return;
        const ship_part = tile.getShipPart() orelse return;
        const repair_costs = PartStats.getRepairCosts(ship_part.kind);
        const is_broken = PartStats.isBroken(ship_part);
        const can_repair = is_broken and self.logic.canRepair(ship, repair_costs);

        const can_weld = world.research_manager.isUnlocked(.welding);

        var repair_label_buffer: [128]u8 = undefined;
        var repair_label: []const u8 = "Repair";

        if (repair_costs.len > 0) {
            var stream = std.io.fixedBufferStream(&repair_label_buffer);
            const writer = stream.writer();
            try writer.print("Repair (", .{});
            for (repair_costs, 0..) |cost, i| {
                if (i > 0) try writer.print(", ", .{});
                try writer.print("{d} {s}", .{ cost.amount, cost.item.getName() });
            }
            try writer.print(")", .{});
            repair_label = stream.getWritten();
        }

        const Action = enum { rotate, repair, dismantle };
        var actions: [3]Action = undefined;
        var items_buf: [3]DropdownItem = undefined;
        var count: usize = 0;

        if (ship_part.rotation != null) {
            actions[count] = .rotate;
            items_buf[count] = DropdownItem{ .text = "Rotate [R]", .is_enabled = ship_part.rotation != null };
            count += 1;
        }

        if (can_weld) {
            actions[count] = .repair;
            items_buf[count] = DropdownItem{ .text = repair_label, .is_enabled = can_repair };
            count += 1;
        }

        actions[count] = .dismantle;
        items_buf[count] = DropdownItem{ .text = "Dismantle", .is_enabled = true };
        count += 1;

        const result = try renderer.ui.dropdown(self.tile_menu_x, self.tile_menu_y, items_buf[0..count], renderer.font);

        if (result.selected_index) |index| {
            switch (actions[index]) {
                .rotate => ShipLogic.rotateTile(ship, self.tile_menu_tile_x, self.tile_menu_tile_y),
                .repair => try self.logic.repairTile(ship, world, self.tile_menu_tile_x, self.tile_menu_tile_y),
                .dismantle => ShipLogic.removeTile(ship, self.tile_menu_tile_x, self.tile_menu_tile_y),
            }
            self.is_tile_menu_open = false;
        } else if (!result.rect.contains(.{ .x = input.mouse.x, .y = input.mouse.y })) {
            if (input.mouse.is_left_clicked) {
                self.is_tile_menu_open = false;
                return;
            }
        }
    }
};
