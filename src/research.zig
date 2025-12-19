const std = @import("std");

const Resource = @import("resource.zig").Resource;

pub const ResearchId = enum {
    welding,
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

    pub fn reportResourcePickup(self: *Self, material: Resource, amount: u32) bool {
        const current = self.total_resources.get(material) orelse 0;
        const new_total = current + amount;
        self.total_resources.put(material, new_total);

        var newly_unlocked = false;

        if (material == .iron and new_total >= 10) {
            if (self.unlock(.welding)) newly_unlocked = true;
        }

        // if (material == .carbon and new_total >= 20) {
        //     if (self.unlock(.coal_generator)) newly_unlocked = true;
        // }

        return newly_unlocked;
    }

    // pub fn reportRepair(self: *Self, component_name: []const u8) bool {
    //     if (std.mem.eql(u8, component_name, "broken_thruster")) {
    //         return self.unlock(.standard_thruster);
    //     }
    //     if (std.mem.eql(u8, component_name, "broken_mining_laser")) {
    //         return self.unlock(.mining_beam);
    //     }
    //     return false;
    // }

    fn unlock(self: *ResearchManager, id: ResearchId) bool {
        if (self.unlocked.contains(id)) {
            return false;
        }

        std.log.info("Research: Unlocked={any}", .{id});

        self.unlocked.insert(id);

        return true;
    }
};
