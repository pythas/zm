const std = @import("std");

const PartKind = @import("tile.zig").PartKind;

pub const PartStats = struct {
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
            1 => 30_000.0,
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
