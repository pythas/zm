const std = @import("std");

pub const PartStats = struct {
    pub fn getEnginePower(tier: u8) f32 {
        switch (tier) {
            1 => 50_000.0,
            2 => 100_000.0,
            3 => 200_000.0,
            else => 0.0,
        }
    }
};
