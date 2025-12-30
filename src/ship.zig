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
            .railgun => "Railgun",
            .smart_core => "Smart Core",
        };
    }

    pub fn getMaxHealth(kind: PartKind, tier: u8) f32 {
        _ = tier;
        return switch (kind) {
            .smart_core => 250.0,
            else => 100.0,
        };
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
            .railgun => 4.0,
            .smart_core => 5.0,
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
            .smart_core => &.{
                .{ .item = .{ .resource = .gold }, .amount = 50 },
                .{ .item = .{ .resource = .uranium }, .amount = 10 },
            },
            else => &[_]RepairCost{},
        };
    }

    pub fn getEnginePower(tier: u8) f32 {
        return switch (tier) {
            1 => 15_000.0,
            2 => 100_000.0,
            3 => 200_000.0,
            4 => 500_000.0, // High tier for drones
            else => 0.0,
        };
    }

    pub fn getLaserRangeSq(tier: u8, is_broken: bool) f32 {
        var range: f32 = switch (tier) {
            1 => 200.0,
            2 => 300.0,
            3 => 400.0,
            4 => 500.0,
            else => 0.0,
        };

        if (is_broken) {
            range *= 0.5;
        }

        return range * range;
    }

    pub fn getLaserDamage(tier: u8) f32 {
        return switch (tier) {
            1 => 10.0,
            2 => 15.0,
            3 => 20.0,
            4 => 25.0,
            else => 0.0,
        };
    }

    pub fn getLaserRadius(tier: u8) u8 {
        return switch (tier) {
            1 => 0,
            2 => 1,
            3 => 2,
            4 => 2,
            else => 0,
        };
    }

    pub fn getStorageSlotLimit(tier: u8) u8 {
        return switch (tier) {
            1 => 4,
            2 => 8,
            3 => 16,
            4 => 32,
            else => 0,
        };
    }

    pub fn getRailgunPower(tier: u8) f32 {
        return switch (tier) {
            1 => 200.0,
            2 => 500.0,
            3 => 1000.0,
            4 => 1500.0,
            else => 0.0,
        };
    }

    pub fn getRailgunRange(tier: u8) f32 {
        return switch (tier) {
            1 => 2000.0,
            2 => 3000.0,
            3 => 5000.0,
            4 => 6000.0,
            else => 0.0,
        };
    }

    pub fn getRailgunCooldown(tier: u8) f32 {
        return switch (tier) {
            1 => 0.25,
            2 => 0.20,
            3 => 0.15,
            4 => 0.10,
            else => 1.0,
        };
    }

    pub fn getRailgunImpulseMultiplier() f32 {
        return 40.0;
    }
};
