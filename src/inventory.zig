const std = @import("std");

const Resource = @import("resource.zig").Resource;
const ResourceStats = @import("resource.zig").ResourceStats;
const PartKind = @import("tile.zig").PartKind;
const ResearchId = @import("research.zig").ResearchId;

pub const Tool = enum(u8) {
    welding = 0,
};

pub const Recipe = enum(u8) {
    chemical_thruster = 0,
    laser,
    railgun,
    radar,
    storage,
};

pub const RecipeStats = struct {
    pub const Cost = struct {
        item: Item,
        amount: u32,
    };

    pub fn getCost(recipe: Recipe) []const Cost {
        return switch (recipe) {
            .chemical_thruster => &[_]Cost{
                .{ .item = .{ .resource = .iron }, .amount = 20 },
            },
            .laser => &[_]Cost{
                .{ .item = .{ .resource = .iron }, .amount = 40 },
            },
            .railgun => &[_]Cost{
                .{ .item = .{ .resource = .iron }, .amount = 10 },
            },
            .radar => &[_]Cost{
                .{ .item = .{ .resource = .iron }, .amount = 15 },
            },
            .storage => &[_]Cost{
                .{ .item = .{ .resource = .iron }, .amount = 50 },
            },
        };
    }

    pub fn getResult(recipe: Recipe) Item {
        return switch (recipe) {
            .chemical_thruster => .{ .component = .chemical_thruster },
            .laser => .{ .component = .laser },
            .railgun => .{ .component = .railgun },
            .radar => .{ .component = .radar },
            .storage => .{ .component = .storage },
        };
    }

    pub fn getName(recipe: Recipe) []const u8 {
        return switch (recipe) {
            .chemical_thruster => "Chemical Thruster",
            .laser => "Laser",
            .railgun => "Railgun",
            .radar => "Radar",
            .storage => "Storage",
        };
    }

    pub fn getDisplayName(recipe: Recipe) []const u8 {
        return switch (recipe) {
            .chemical_thruster => "Chemical Thruster\nCost: 20 iron",
            .laser => "Laser\nCost: 40 iron",
            .railgun => "Railgun\nCost: 10 iron",
            .radar => "Radar\nCost: 15 iron",
            .storage => "Storage\nCost: 50 iron",
        };
    }

    pub fn getResearchId(recipe: Recipe) ResearchId {
        return switch (recipe) {
            .chemical_thruster => .chemical_thruster,
            .laser => .laser,
            .railgun => .railgun,
            .radar => .radar,
            .storage => .storage,
        };
    }
};

pub const Item = union(enum) {
    none,
    resource: Resource,
    tool: Tool,
    recipe: Recipe,
    component: PartKind,

    pub fn eql(self: Item, other: Item) bool {
        return switch (self) {
            .none => other == .none,
            .resource => |r| if (other == .resource) r == other.resource else false,
            .tool => |t| if (other == .tool) t == other.tool else false,
            .recipe => |r| if (other == .recipe) r == other.recipe else false,
            .component => |c| if (other == .component) c == other.component else false,
        };
    }

    pub fn getMaxStack(self: Item) u32 {
        return switch (self) {
            .none => 0,
            .resource => |r| ResourceStats.getMaxStack(r),
            .tool => 1,
            .recipe => 1,
            .component => 4, // TODO: load from elsewhere
        };
    }

    pub fn getName(self: Item) []const u8 {
        return switch (self) {
            .none => "None",
            .resource => |r| ResourceStats.getName(r),
            .tool => |t| switch (t) {
                .welding => "Basic Welding",
            },
            .recipe => |r| RecipeStats.getDisplayName(r),
            .component => |c| switch (c) {
                .chemical_thruster => "Chemical Thruster",
                .laser => "Laser",
                .railgun => "Railgun",
                .radar => "Radar",
                .storage => "Storage",
                else => "N/A",
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

    pub fn init(allocator: std.mem.Allocator, slot_limit: u32) !Self {
        var stacks = try std.ArrayList(Stack).initCapacity(allocator, slot_limit);
        for (0..slot_limit) |_| {
            stacks.appendAssumeCapacity(.{});
        }

        return .{
            .allocator = allocator,
            .stacks = stacks,
            .slot_limit = slot_limit,
        };
    }

    pub fn deinit(self: *Inventory) void {
        self.stacks.deinit();
    }

    pub fn resize(self: *Inventory, new_limit: u32) !void {
        if (new_limit > self.stacks.items.len) {
            const diff = new_limit - self.stacks.items.len;

            try self.stacks.ensureTotalCapacity(new_limit);

            for (0..diff) |_| {
                self.stacks.appendAssumeCapacity(.{});
            }
        } else if (new_limit < self.stacks.items.len) {
            // TODO: handle shrinking and dropping items?
            // Now we simply delete items
            self.stacks.shrinkAndFree(new_limit);
        }
        self.slot_limit = new_limit;
    }

    pub fn add(self: *Inventory, item: Item, amount: u32) !AddResult {
        if (item == .none or amount == 0) {
            return .{ .added = 0, .remaining = amount };
        }

        std.log.info("Inventory: Adding item={any}, amount={d}", .{ item, amount });

        var remaining = amount;
        var added: u32 = 0;

        // try to stack on existing items
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

        // try to fill empty slots
        while (remaining > 0) {
            var found_empty = false;
            for (self.stacks.items) |*stack| {
                if (stack.item == .none) {
                    const max = item.getMaxStack();
                    const take = @min(remaining, max);

                    stack.item = item;
                    stack.amount = take;

                    remaining -= take;
                    added += take;
                    found_empty = true;
                    break;
                }
            }

            if (!found_empty) break;
        }

        return .{ .added = added, .remaining = remaining };
    }
};
