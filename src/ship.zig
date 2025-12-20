const std = @import("std");

const PartKind = @import("tile.zig").PartKind;
const ShipPartTileType = @import("tile.zig").ShipPartTileType;

pub const PartStats = struct {
    pub fn getName(kind: PartKind) []const u8 {
        return switch (kind) {
            .hull => "Hull",
            .reactor => "Reactor",
            .engine => "Engine",
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
            .engine => 2.0,
            .hull => 1.0,
            .laser => 1.0,
            else => 1.0,
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

    pub fn getLaserRangeSq(tier: u8) f32 {
        const range: f32 = switch (tier) {
            1 => 100.0,
            2 => 160.0,
            3 => 320.0,
            else => 0.0,
        };

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
};
