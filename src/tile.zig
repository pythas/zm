const std = @import("std");

const Vec2 = @import("vec2.zig").Vec2;

pub const tilemapWidth = 16;
pub const tilemapHeight = 16;

pub const TileCoords = struct {
    x: usize,
    y: usize,
};

pub const TileReference = struct {
    object_id: u64,
    tile_x: usize,
    tile_y: usize,
};

pub const TileCategory = enum(u8) {
    Empty,
    Terrain,
    Hull,
    Engine,
    RCS,
    Laser,
};

pub const BaseMaterial = enum(u8) {
    Vacuum,
    Rock,
    Regolith,
    Ice,
    Metal,
    Wood,
    Composite,
    Organic,
};

pub const Ore = enum(u8) {
    Iron,
    Nickel,
    Cobalt,
    Copper,
    Gold,
    Platinum,
    Water,
    Carbon,
    Silicon,
    RareEarths,
};

pub const OreAmount = struct {
    ore: Ore,
    richness: u8,
};

pub const Composition = struct {
    const Self = @This();

    base: BaseMaterial,
    ores: std.ArrayList(OreAmount),

    pub fn init(
        allocator: std.mem.Allocator,
        base: BaseMaterial,
    ) !Self {
        return .{
            .base = base,
            .ores = std.ArrayList(OreAmount).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.ores.deinit();
    }

    pub fn setOre(self: *Self, ore: Ore, richness: u8) !void {
        for (self.ores.items) |*slot| {
            if (slot.ore == ore) {
                slot.richness = richness;
                return;
            }
        }
        try self.ores.append(.{ .ore = ore, .richness = richness });
    }
};

pub const SpriteSheet = enum(u8) {
    World = 0,
    Asteroids = 1,
    Ships = 2,
};

pub const Direction = enum(u8) {
    North = 0,
    East = 1,
    South = 2,
    West = 3,
};

pub const Directions: []const struct {
    direction: Direction,
    dx: i32,
    dy: i32,
} = &.{
    .{ .direction = Direction.North, .dx = 0, .dy = -1 },
    .{ .direction = Direction.South, .dx = 0, .dy = 1 },
    .{ .direction = Direction.East, .dx = 1, .dy = 0 },
    .{ .direction = Direction.West, .dx = -1, .dy = 0 },
};

pub const Offset = struct {
    dx: isize,
    dy: isize,
};

pub const Tile = struct {
    const Self = @This();

    category: TileCategory,
    composition: Composition,
    sheet: SpriteSheet,
    sprite: u16,
    rotation: Direction = .North,

    pub fn init(
        allocator: std.mem.Allocator,
        category: TileCategory,
        base: BaseMaterial,
        sheet: SpriteSheet,
        sprite: u16,
    ) !Self {
        return .{
            .category = category,
            .composition = try Composition.init(allocator, base),
            .sheet = sheet,
            .sprite = sprite,
        };
    }

    pub fn initEmpty(allocator: std.mem.Allocator) !Self {
        return .{
            .category = .Empty,
            .composition = try Composition.init(allocator, .Vacuum),
            .sheet = .World,
            .sprite = 0,
        };
    }
};
