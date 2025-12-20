const std = @import("std");

const Resource = @import("resource.zig").Resource;
const ResourceStats = @import("resource.zig").ResourceStats;

pub const Tool = enum {
    welding,
};

pub const Item = union(enum) {
    none,
    resource: Resource,
    tool: Tool,

    pub fn eql(self: Item, other: Item) bool {
        return switch (self) {
            .none => other == .none,
            .resource => |r| if (other == .resource) r == other.resource else false,
            .tool => |t| if (other == .tool) t == other.tool else false,
        };
    }

    pub fn getMaxStack(self: Item) u32 {
        return switch (self) {
            .none => 0,
            .resource => |r| ResourceStats.getMaxStack(r),
            .tool => 1,
        };
    }

    pub fn getName(self: Item) []const u8 {
        return switch (self) {
            .none => "None",
            .resource => |r| ResourceStats.getName(r),
            .tool => |t| switch (t) {
                .welding => "Welding Tool",
            },
        };
    }
};

pub const Stack = struct {
    item: Item = .none,
    amount: u32 = 0,
};

pub const AddResult = struct {
    added: u32,
    remaining: u32,
};

pub const Inventory = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    stacks: std.ArrayList(Stack),
    slot_limit: u32,

    pub fn init(allocator: std.mem.Allocator, slot_limit: u32) Self {
        return .{
            .allocator = allocator,
            .stacks = std.ArrayList(Stack).init(allocator),
            .slot_limit = slot_limit,
        };
    }

    pub fn deinit(self: *Inventory) void {
        self.stacks.deinit();
    }

    pub fn add(self: *Inventory, item: Item, amount: u32) !AddResult {
        if (item == .none or amount == 0) {
            return .{ .added = 0, .remaining = amount };
        }

        std.log.info("Inventory: Adding item={any}, amount={d}", .{ item, amount });

        var remaining = amount;
        var added: u32 = 0;

        for (self.stacks.items) |*stack| {
            if (stack.item.eql(item)) {
                const max = item.getMaxStack();

                if (stack.amount < max) {
                    const take = @min(remaining, max - stack.amount);

                    stack.amount += take;
                    remaining -= take;
                    added += take;

                    if (remaining == 0) {
                        return .{ .added = added, .remaining = 0 };
                    }
                }
            }
        }

        while (remaining > 0) {
            if (self.stacks.items.len >= self.slot_limit) break;

            const max = item.getMaxStack();
            const take = @min(remaining, max);

            try self.stacks.append(Stack{
                .item = item,
                .amount = take,
            });
            remaining -= take;
            added += take;
        }

        return .{ .added = added, .remaining = remaining };
    }
};
