const std = @import("std");

pub const ResearchId = enum {
    welding,
};

pub const ResearchManager = struct {
    const Self = @This();

    unlocked: std.EnumSet(ResearchId),

    pub fn init() Self {
        return .{
            .unlocked = std.EnumSet(ResearchId).initEmpty(),
        };
    }

    fn unlock(self: *ResearchManager, id: ResearchId) bool {
        if (self.unlocked.contains(id)) {
            return false;
        }

        self.unlocked.insert(id);

        return true;
    }
};
