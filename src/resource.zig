const std = @import("std");

pub const Resource = enum(u8) {
    none = 0,
    iron,
    nickel,
    copper,
    carbon,
    gold,
    platinum,
    titanium,
    uranium,
};

pub const ResourceStats = struct {
    pub fn getName(res: Resource) []const u8 {
        return switch (res) {
            .none => "None",
            .iron => "Iron",
            .nickel => "Nickel",
            .copper => "Copper",
            .carbon => "Carbon",
            .gold => "Gold",
            .platinum => "Platinum",
            .titanium => "Titanium",
            .uranium => "Uranium",
        };
    }

    pub fn getDensity(res: Resource) f32 {
        return switch (res) {
            .none => 0.0,
            .iron => 1.5,
            .nickel => 1.4,
            .copper => 1.4,
            .carbon => 0.8,
            .gold => 2.5,
            .platinum => 2.6,
            .titanium => 0.9,
            .uranium => 3.0,
        };
    }

    pub fn getMaxStack(res: Resource) u32 {
        return switch (res) {
            .none => 0,
            else => 32,
        };
    }
};
