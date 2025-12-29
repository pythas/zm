const std = @import("std");

const PartKind = @import("tile.zig").PartKind;
const ShipPartTileType = @import("tile.zig").ShipPartTileType;
const Item = @import("inventory.zig").Item;

pub const RepairCost = struct {
    item: Item,
    amount: u32,
};

pub const PartStats = struct {
    pub fn getName(kind: PartKind) []const u8 {
        return switch (kind) {
            .hull => "Hull",
            .reactor => "Reactor",
            .chemical_thruster => "Chemical Thruster",
            .laser => "Laser",
            .storage => "Storage",
        };
    }

    pub fn getMaxHealth(kind: PartKind, tier: u8) f32 {
        _ = kind;
        _ = tier;
        return 100.0;
    }

    pub fn getFunctionalThreshold(kind: PartKind, tier: u8) f32 {
        _ = kind;
        _ = tier;
        return 30.0;
    }

    pub fn isBroken(part: ShipPartTileType) bool {
        return part.health < getFunctionalThreshold(part.kind, part.tier);
    }

    pub fn getDensity(kind: PartKind) f32 {
        return switch (kind) {
            .chemical_thruster => 2.0,
            .hull => 1.0,
            .laser => 1.0,
            .reactor => 1.5,
            .storage => 0.5,
        };
    }

    pub fn getRepairCosts(kind: PartKind) []const RepairCost {
        return switch (kind) {
            .chemical_thruster => &.{
                .{ .item = .{ .resource = .iron }, .amount = 10 },
            },
            .hull => &.{
                .{ .item = .{ .resource = .iron }, .amount = 5 },
            },
            .laser => &.{
                .{ .item = .{ .resource = .iron }, .amount = 15 },
                .{ .item = .{ .resource = .copper }, .amount = 5 },
            },
            else => &[_]RepairCost{},
        };
    }

    pub fn getEnginePower(tier: u8) f32 {
        return switch (tier) {
            1 => 15_000.0,
            2 => 100_000.0,
            3 => 200_000.0,
            else => 0.0,
        };
    }

    pub fn getLaserRangeSq(tier: u8, is_broken: bool) f32 {
        var range: f32 = switch (tier) {
            1 => 100.0,
            2 => 160.0,
            3 => 320.0,
            else => 0.0,
        };

        if (is_broken) {
            range *= 0.5;
        }

        return range * range;
    }

    pub fn getLaserRadius(tier: u8) u8 {
        return switch (tier) {
            1 => 0,
            2 => 1,
            3 => 2,
            else => 0,
        };
    }

    pub fn getStorageSlotLimit(tier: u8) u8 {
        return switch (tier) {
            1 => 4,
            2 => 8,
            3 => 16,
            else => 0,
        };
    }
};
