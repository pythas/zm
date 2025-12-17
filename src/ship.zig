const std = @import("std");

const PartKind = @import("tile.zig").PartKind;

pub const PartStats = struct {
    pub fn getDensity(kind: PartKind) f32 {
        return switch (kind) {
            .Engine => 2.0,
            .Hull => 1.0,
            .Laser => 1.0,
            .RCS => 0.5,
        };
    }

    pub fn getEnginePower(tier: u8) f32 {
        return switch (tier) {
            1 => 50_000.0,
            2 => 100_000.0,
            3 => 200_000.0,
            else => 0.0,
        };
    }
};
