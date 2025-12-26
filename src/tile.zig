const std = @import("std");

const Vec2 = @import("vec2.zig").Vec2;

pub const tilemapWidth = 16;
pub const tilemapHeight = 16;

const Resource = @import("resource.zig").Resource;

pub const PartKind = enum(u8) {
    hull,
    reactor,
    chemical_thruster,
    laser,
    storage,
};

pub const BaseMaterial = enum(u8) {
    vacuum,
    rock,
};

pub const ResourceAmount = struct {
    resource: Resource,
    amount: u8,
};

pub const TileType = enum {
    empty,
    terrain,
    ship_part,
};

pub const TerrainTileType = struct {
    const Self = @This();

    base_material: BaseMaterial,
    variant: u8 = 0,
    resources: std.BoundedArray(ResourceAmount, 4) = .{},

    pub fn getMostCommonResource(self: Self) ?ResourceAmount {
        var max: ?u8 = null;
        var best: ?ResourceAmount = null;

        for (self.resources.slice()) |resource_amount| {
            if (max == null or resource_amount.amount > max.?) {
                max = resource_amount.amount;
                best = resource_amount;
            }
        }

        return best;
    }
};

pub const ShipPartTileType = struct {
    const Self = @This();

    kind: PartKind,
    tier: u8,
    health: f32,
    rotation: Direction = .north,
};

pub const TileData = union(TileType) {
    empty: void,
    terrain: TerrainTileType,
    ship_part: ShipPartTileType,
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
    font = 0,
    terrain = 1,
    ships = 2,
    resources = 3,
    tools = 4,
    recipe = 5,
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
            .sheet = .terrain,
            .index = 0,
        };
    }
};

pub const Direction = enum(u8) {
    north = 0,
    east = 1,
    south = 2,
    west = 3,

    pub fn toRad(self: Direction) f32 {
        return switch (self) {
            .north => 0.0,
            .east => std.math.pi / 2.0,
            .south => std.math.pi,
            .west => 3.0 * std.math.pi / 2.0,
        };
    }
};

pub const Offset = struct {
    dx: i32,
    dy: i32,
};

pub const Directions = [_]struct { direction: Direction, offset: Offset }{
    .{ .direction = .north, .offset = .{ .dx = 0, .dy = -1 } },
    .{ .direction = .east, .offset = .{ .dx = 1, .dy = 0 } },
    .{ .direction = .south, .offset = .{ .dx = 0, .dy = 1 } },
    .{ .direction = .west, .offset = .{ .dx = -1, .dy = 0 } },
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
            .data = .empty,
        };
    }

    pub fn getShipPart(self: Self) ?ShipPartTileType {
        return switch (self.data) {
            .ship_part => |ship| ship,
            else => null,
        };
    }

    pub fn getPartKind(self: Self) ?PartKind {
        return switch (self.data) {
            .ship_part => |ship| ship.kind,
            else => null,
        };
    }

    pub fn getTier(self: Self) ?u8 {
        return switch (self.data) {
            .ship_part => |ship| ship.tier,
            else => null,
        };
    }

    pub fn isTerrain(self: Self) bool {
        return switch (self.data) {
            .terrain => true,
            else => false,
        };
    }

    pub fn isShipPart(self: Self) bool {
        return switch (self.data) {
            .ship_part => true,
            else => false,
        };
    }
};
