const std = @import("std");
const Vec2 = @import("../vec2.zig").Vec2;
const TileObject = @import("../tile_object.zig").TileObject;
const Item = @import("../inventory.zig").Item;
const Inventory = @import("../inventory.zig").Inventory;
const PartStats = @import("../ship.zig").PartStats;

pub const InventoryLogic = struct {
    pub fn initInventories(ship: *TileObject) !void {
        const tile_refs = try ship.getTilesByPartKind(.storage);
        defer ship.allocator.free(tile_refs);

        for (tile_refs) |tile_ref| {
            const tile = ship.getTile(tile_ref.tile_x, tile_ref.tile_y) orelse continue;
            const part = tile.getShipPart() orelse continue;
            if (PartStats.isBroken(part)) continue;

            _ = try addInventory(ship, tile_ref.tile_x, tile_ref.tile_y, PartStats.getStorageSlotLimit(part.tier));
        }
    }

    pub fn getInventory(ship: *TileObject, x: usize, y: usize) ?*Inventory {
        if (x >= ship.width or y >= ship.height) {
            return null;
        }

        const index = y * ship.width + x;
        return ship.inventories.getPtr(index);
    }

    pub fn addInventory(ship: *TileObject, x: usize, y: usize, slot_limit: u32) !*Inventory {
        const index = y * ship.width + x;

        if (ship.inventories.getPtr(index)) |inventory| {
            try inventory.resize(slot_limit);
            return inventory;
        }

        const inventory = try Inventory.init(ship.allocator, slot_limit);
        try ship.inventories.put(index, inventory);

        return ship.inventories.getPtr(index).?;
    }

    pub fn addItemToInventory(
        ship: *TileObject,
        item: Item,
        amount: u32,
        from_position: Vec2,
    ) !u32 {
        const storage_list = try ship.getTilesByPartKindSortedByDist(.storage, from_position);
        defer ship.allocator.free(storage_list);

        var remaining = amount;

        for (storage_list) |storage| {
            const inventory = getInventory(ship, storage.tile_x, storage.tile_y) orelse continue;

            const result = try inventory.add(item, remaining);
            remaining = @intCast(result.remaining);

            if (remaining == 0) {
                break;
            }
        }

        return remaining;
    }

    pub fn getInventoryCountByItem(ship: *TileObject, item: Item) u32 {
        var count: u32 = 0;

        var it = ship.inventories.valueIterator();
        while (it.next()) |inv| {
            for (inv.stacks.items) |stack| {
                if (stack.item.eql(item)) {
                    count += stack.amount;
                }
            }
        }

        return count;
    }

    pub fn removeNumberOfItemsFromInventory(ship: *TileObject, item: Item, amount: u32) void {
        var remaining = amount;

        var it = ship.inventories.valueIterator();
        while (it.next()) |inv| {
            for (inv.stacks.items) |*stack| {
                if (remaining == 0) {
                    return;
                }

                if (stack.item.eql(item) and stack.amount > 0) {
                    const take = @min(stack.amount, remaining);

                    stack.amount -= take;
                    remaining -= take;

                    if (stack.amount == 0) {
                        stack.item = .none;
                    }
                }
            }
        }
    }
};
