const std = @import("std");

const Resource = @import("resource.zig").Resource;

pub const ResearchId = enum {
    welding,
    chemical_thruster,
    laser,
};

pub const ResearchManager = struct {
    const Self = @This();

    unlocked: std.EnumSet(ResearchId),

    total_resources: std.EnumMap(Resource, u32),

    pub fn init() ResearchManager {
        return .{
            .unlocked = std.EnumSet(ResearchId).initEmpty(),
            .total_resources = std.EnumMap(Resource, u32).initFull(0),
        };
    }

    pub fn unlockAll(self: *Self) void {
        inline for (std.meta.fields(ResearchId)) |field| {
            self.unlocked.insert(@enumFromInt(field.value));
        }
        std.log.info("Research: CHEAT - All Tech Unlocked", .{});
    }

    pub fn reportResourcePickup(self: *Self, material: Resource, amount: u32) bool {
        const current = self.total_resources.get(material) orelse 0;
        const new_total = current + amount;
        self.total_resources.put(material, new_total);

        var newly_unlocked = false;

        if (material == .iron and new_total >= 10) {
            if (self.unlock(.welding)) newly_unlocked = true;
        }

        return newly_unlocked;
    }

    pub fn reportRepair(self: *Self, component_name: []const u8) bool {
        if (std.mem.eql(u8, component_name, "broken_chemical_thruster")) {
            return self.unlock(.chemical_thruster);
        }

        if (std.mem.eql(u8, component_name, "broken_laser")) {
            return self.unlock(.laser);
        }

        return false;
    }

    fn unlock(self: *ResearchManager, id: ResearchId) bool {
        if (self.unlocked.contains(id)) {
            return false;
        }

        std.log.info("Research: Unlocked={any}", .{id});

        self.unlocked.insert(id);

        return true;
    }

    pub fn isUnlocked(self: ResearchManager, id: ResearchId) bool {
        return self.unlocked.contains(id);
    }
};
