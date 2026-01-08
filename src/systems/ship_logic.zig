const std = @import("std");
const Tile = @import("../tile.zig").Tile;
const Direction = @import("../tile.zig").Direction;
const PartKind = @import("../tile.zig").PartKind;
const TileObject = @import("../tile_object.zig").TileObject;
const World = @import("../world.zig").World;
const Item = @import("../inventory.zig").Item;
const Stack = @import("../inventory.zig").Stack;
const Recipe = @import("../inventory.zig").Recipe;
const RecipeStats = @import("../inventory.zig").RecipeStats;
const PartStats = @import("../ship.zig").PartStats;
const RepairCost = @import("../ship.zig").RepairCost;
const ship_serialization = @import("../ship_serialization.zig");
const InventoryLogic = @import("inventory_logic.zig").InventoryLogic;
const config = @import("../config.zig");

pub const CraftingTask = struct {
    recipe: Recipe,
    progress: f32,
    duration: f32,
};

pub const ShipLogic = struct {
    const Self = @This();

    active_crafting: ?CraftingTask = null,

    pub fn updateCrafting(self: *Self, dt: f32, world: *World, ship: *TileObject) !void {
        _ = world;
        var task = &(self.active_crafting orelse return);
        task.progress += dt;

        if (task.progress < task.duration) {
            return;
        }

        const result = RecipeStats.getResult(task.recipe);
        const remaining = try InventoryLogic.addItemToInventory(ship, result, 1, ship.position);

        if (remaining == 0) {
            std.log.info("ShipManagement: Constructed {s}", .{RecipeStats.getName(task.recipe)});
        } else {
            std.log.warn("ShipManagement: Failed to add {s} to inventory (no space?). Refunding resources.", .{RecipeStats.getName(task.recipe)});

            const costs = RecipeStats.getCost(task.recipe);
            for (costs) |cost| {
                _ = try InventoryLogic.addItemToInventory(ship, cost.item, cost.amount, ship.position);
            }
        }

        self.active_crafting = null;
    }

    pub fn rotateTile(ship: *TileObject, x: usize, y: usize) void {
        if (ship.getTile(x, y)) |tile| {
            if (tile.data == .ship_part) {
                var new_tile = tile.*;
                if (new_tile.data.ship_part.rotation) |rot| {
                    new_tile.data.ship_part.rotation = @enumFromInt((@intFromEnum(rot) + 1) % 4);
                    ship.setTile(x, y, new_tile);
                }
            }
        }
    }

    pub fn removeTile(ship: *TileObject, x: usize, y: usize) void {
        ship.setTile(x, y, Tile.initEmpty() catch unreachable);
    }

    pub fn repairTile(self: *Self, ship: *TileObject, world: *World, x: usize, y: usize) !void {
        const tile = ship.getTile(x, y) orelse return;
        const ship_part = tile.getShipPart() orelse return;
        const repair_costs = PartStats.getRepairCosts(ship_part.kind);

        if (self.canRepair(ship, repair_costs)) {
            var new_tile = tile.*;
            new_tile.data.ship_part.health = PartStats.getFunctionalThreshold(new_tile.data.ship_part.kind, new_tile.data.ship_part.tier);
            ship.setTile(x, y, new_tile);

            for (repair_costs) |repair_cost| {
                InventoryLogic.removeNumberOfItemsFromInventory(ship, repair_cost.item, repair_cost.amount);
            }

            var unlocked = false;
            switch (ship_part.kind) {
                .chemical_thruster => unlocked = world.research_manager.reportRepair("broken_chemical_thruster"),
                .laser => unlocked = world.research_manager.reportRepair("broken_laser"),
                .radar => unlocked = world.research_manager.reportRepair("broken_radar"),
                .storage => unlocked = world.research_manager.reportRepair("broken_storage"),
                else => {},
            }

            if (unlocked) {
                 var buf: [64]u8 = undefined;
                 const name = PartStats.getName(ship_part.kind);
                 const text = std.fmt.bufPrint(&buf, "Unlocked: {s}", .{name}) catch "Unlocked Tech";
                 world.notifications.add(text, .{ .r = 1.0, .g = 0.8, .b = 0.0, .a = 1.0 }, .manual_dismiss);
            }

            try InventoryLogic.initInventories(ship);
        }
    }

    pub fn canRepair(self: *Self, ship: *TileObject, repair_costs: []const RepairCost) bool {
        _ = self;
        for (repair_costs) |repair_cost| {
            const count = InventoryLogic.getInventoryCountByItem(ship, repair_cost.item);

            if (count < repair_cost.amount) {
                return false;
            }
        }

        return true;
    }

    pub fn tryCraft(self: *Self, ship: *TileObject, recipe: Recipe) !void {
        if (self.active_crafting != null) {
            return;
        }

        const costs = RecipeStats.getCost(recipe);

        for (costs) |cost| {
            const count = InventoryLogic.getInventoryCountByItem(ship, cost.item);

            if (count < cost.amount) {
                return;
            }
        }

        for (costs) |cost| {
            InventoryLogic.removeNumberOfItemsFromInventory(ship, cost.item, cost.amount);
        }

        self.active_crafting = .{
            .recipe = recipe,
            .progress = 0.0,
            .duration = RecipeStats.getDuration(recipe),
        };
    }

    pub fn save(allocator: std.mem.Allocator, ship: *TileObject) void {
        ship_serialization.saveShip(allocator, ship.*, config.assets.ship_json) catch |err| {
            std.debug.print("Failed to save ship: {}\n", .{err});
        };
    }

    pub fn constructPart(ship: *TileObject, x: usize, y: usize, part_kind: PartKind, cursor_item: *Stack) !void {
        if (ship.getTile(x, y)) |tile| {
            if (tile.data == .empty) {
                const tier = 1; // Default tier
                const health = PartStats.getMaxHealth(part_kind, tier);
                const rotation: ?Direction = if (part_kind == .chemical_thruster) .north else null;
                const new_tile = Tile.init(.{
                    .ship_part = .{
                        .kind = part_kind,
                        .tier = tier,
                        .health = health,
                        .rotation = rotation,
                    },
                }) catch unreachable;

                ship.setTile(x, y, new_tile);

                cursor_item.amount -= 1;
                if (cursor_item.amount == 0) {
                    cursor_item.* = .{};
                }

                try InventoryLogic.initInventories(ship);
            }
        }
    }

    pub fn repairAll(ship: *TileObject) void {
        for (ship.tiles, 0..) |tile, i| {
            if (tile.data == .ship_part) {
                ship.tiles[i].data.ship_part.health = 100.0; // TODO: Load from PartStats
            }
        }
        ship.dirty = true;
    }
};
