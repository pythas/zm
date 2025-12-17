const std = @import("std");
const Vec2 = @import("vec2.zig").Vec2;
pub const tilemapWidth = 16;
pub const tilemapHeight = 16;

pub const PartKind = enum(u8) {
    Hull,
    Engine,
    RCS,
    Laser,
};

pub const BaseMaterial = enum(u8) {
    Vacuum,
    Rock,
    Metal,
    Ice,
};

pub const Ore = enum(u8) {
    None,
    Iron,
    Nickel,
    Cobalt,
    Gold,
    Platinum,
};

pub const OreAmount = struct {
    ore: Ore,
    richness: u8,
};

pub const TileType = enum {
    Empty,
    Terrain,
    ShipPart,
};

pub const TerrainTileType = struct {
    base_material: BaseMaterial,
    ores: [2]OreAmount,
};

pub const ShipPartTileType = struct {
    kind: PartKind,
    tier: u8,
    health: f32,
    variation: u8,
    rotation: Direction = .North,
};

pub const TileData = union(TileType) {
    Empty: void,
    Terrain: TerrainTileType,
    ShipPart: ShipPartTileType,
};

pub const TileCoords = struct {
    x: usize,
    y: usize,
};

pub const TileReference = struct {
    object_id: u64,
    tile_x: usize,
    tile_y: usize,
};

pub const SpriteSheet = enum(u8) {
    World = 0,
    Terrain = 1,
    Ships = 2,
};

pub const Sprite = struct {
    const Self = @This();

    sheet: SpriteSheet,
    index: u16,

    pub fn init(sheet: SpriteSheet, index: u16) Self {
        return .{
            .sheet = sheet,
            .index = index,
        };
    }

    pub fn initEmpty() Self {
        return .{
            .sheet = .World,
            .index = 0,
        };
    }
};

pub const Direction = enum(u8) {
    North = 0,
    East = 1,
    South = 2,
    West = 3,

    pub fn toRad(self: Direction) f32 {
        return switch (self) {
            .North => 0.0,
            .East => std.math.pi / 2.0,
            .South => std.math.pi,
            .West => 3.0 * std.math.pi / 2.0,
        };
    }
};

pub const Offset = struct {
    dx: i32,
    dy: i32,
};

pub const Directions = [_]struct { direction: Direction, offset: Offset }{
    .{ .direction = .North, .offset = .{ .dx = 0, .dy = -1 } },
    .{ .direction = .East, .offset = .{ .dx = 1, .dy = 0 } },
    .{ .direction = .South, .offset = .{ .dx = 0, .dy = 1 } },
    .{ .direction = .West, .offset = .{ .dx = -1, .dy = 0 } },
};

pub const Tile = struct {
    const Self = @This();

    data: TileData,

    pub fn init(
        data: TileData,
    ) !Self {
        return .{
            .data = data,
        };
    }

    pub fn initEmpty() !Self {
        return .{
            .data = .Empty,
        };
    }

    pub fn getShipPart(self: Self) ?ShipPartTileType {
        return switch (self.data) {
            .ShipPart => |ship| ship,
            else => null,
        };
    }

    pub fn getPartKind(self: Self) ?PartKind {
        return switch (self.data) {
            .ShipPart => |ship| ship.kind,
            else => null,
        };
    }

    pub fn getTier(self: Self) ?u8 {
        return switch (self.data) {
            .ShipPart => |ship| ship.tier,
            else => null,
        };
    }

    pub fn isShipPart(self: Self) bool {
        return switch (self.data) {
            .ShipPart => true,
            else => false,
        };
    }
};
