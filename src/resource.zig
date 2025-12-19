const std = @import("std");

pub const Resource = enum(u8) {
    none = 0,
    iron,
    copper,   // Mentioned in DESIGN.md (Zone 1)
    carbon,   // Mentioned in STORY.md (Refuel)
    gold,
    platinum,
    titanium, // Mentioned in DESIGN.md
    uranium,  // Mentioned in DESIGN.md
};

pub const ResourceStats = struct {
    pub fn getName(res: Resource) []const u8 {
        return switch (res) {
            .none => "None",
            .iron => "Iron",
            .copper => "Copper",
            .carbon => "Carbon",
            .gold => "Gold",
            .platinum => "Platinum",
            .titanium => "Titanium",
            .uranium => "Uranium",
        };
    }

    /// Density relative to standard rock (1.0)
    /// Heavier asteroids might imply better loot!
    pub fn getDensity(res: Resource) f32 {
        return switch (res) {
            .none => 0.0,
            .iron => 1.5,
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
            else => 100, // Standard stack size, can be tuned per resource
        };
    }
};
