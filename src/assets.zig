const std = @import("std");

const Sprite = @import("tile.zig").Sprite;
const SpriteSheet = @import("tile.zig").SpriteSheet;
const TileData = @import("tile.zig").TileData;
const BaseMaterial = @import("tile.zig").BaseMaterial;
const PartKind = @import("tile.zig").PartKind;
const TerrainTileType = @import("tile.zig").TerrainTileType;
const ShipPartTileType = @import("tile.zig").ShipPartTileType;
const Resource = @import("resource.zig").Resource;
const Tool = @import("inventory.zig").Tool;
const Recipe = @import("inventory.zig").Recipe;
const PartStats = @import("ship.zig").PartStats;
const rng = @import("rng.zig");

const row_width = 32;

const terrain_sheet: SpriteSheet = .terrain;
const ship_sheet: SpriteSheet = .ships;
const resource_sheet: SpriteSheet = .resources;
const tool_sheet: SpriteSheet = .tools;
const recipe_sheet: SpriteSheet = .recipe;

fn setRow(row: u16, index: u16) u16 {
    return row * row_width + index;
}

pub const Assets = struct {
    pub fn getSprite(data: TileData, mask: u8, x: usize, y: usize) Sprite {
        return switch (data) {
            .empty => Sprite.initEmpty(),
            .terrain => |terrain| getTerrainSprite(terrain, mask, x, y),
            .ship_part => |ship| getShipPartSprite(ship, mask),
        };
    }

    pub fn getResourceSprite(resource: Resource) Sprite {
        if (resource == .none) {
            return Sprite.initEmpty();
        }

        const index = @intFromEnum(resource) - 1;

        return Sprite.init(resource_sheet, @intCast(index));
    }

    pub fn getComponentSprite(part_kind: PartKind) Sprite {
        const index = @intFromEnum(part_kind);

        return Sprite.init(resource_sheet, setRow(15, @intCast(index)));
    }

    pub fn getToolSprite(tool: Tool) Sprite {
        const index = @intFromEnum(tool);

        return Sprite.init(tool_sheet, @intCast(index));
    }

    pub fn getRecipeSprite(recipe: Recipe) Sprite {
        const index = @intFromEnum(recipe);

        return Sprite.init(recipe_sheet, @intCast(index));
    }

    pub fn getTerrainSprite(terrain: TerrainTileType, mask: u8, x: usize, y: usize) Sprite {
        return switch (terrain.base_material) {
            .rock => getRockSprite(terrain, mask, x, y),
            else => Sprite.init(terrain_sheet, 0),
        };
    }

    pub fn getResourceOverlay(resource: Resource, x: usize, y: usize) ?Sprite {
        const base_index: u16 = switch (resource) {
            .iron => 0,
            .nickel => 1,
            .copper => 2,
            .carbon => 3,
            .gold => 4,
            .platinum => 5,
            .titanium => 6,
            .uranium => 7,
            else => return null,
        };

        var seed: u64 = @intCast(x);
        seed = (seed << 32) | @as(u64, @intCast(y));
        var prng = std.Random.DefaultPrng.init(seed);
        const variant = prng.random().uintAtMost(u8, 1); // 0 or 1

        // row 30 for variant 0, row 31 for variant 1
        const row = 30 + variant;

        return Sprite.init(terrain_sheet, setRow(row, base_index));
    }

    pub fn getRockSprite(terrain: TerrainTileType, mask: u8, x: usize, y: usize) Sprite {
        _ = x;
        _ = y;
        const base_row: u16 = @min(terrain.variant, 3);

        const default = Sprite.init(terrain_sheet, setRow(base_row, mask));
        return default;
    }

    pub fn getShipPartSprite(ship: ShipPartTileType, mask: u8) Sprite {
        return switch (ship.kind) {
            .hull => getHullSprite(ship, mask),
            .reactor => getReactorSprite(ship),
            .chemical_thruster => getEngineSprite(ship),
            .laser => getLaserSprite(ship),
            .storage => getStorageSprite(ship),
            .railgun => getRailgunSprite(ship),
            .smart_core => getSmartCoreSprite(ship),
            .radar => getRadarSprite(ship),
        };
    }

    pub fn getHullSprite(ship: ShipPartTileType, mask: u8) Sprite {
        _ = ship;
        return Sprite.init(ship_sheet, setRow(0, mask));
    }

    pub fn getReactorSprite(ship: ShipPartTileType) Sprite {
        var index: u16 = 0;

        if (PartStats.isBroken(ship)) {
            index += 1;
        }

        return Sprite.init(ship_sheet, setRow(2, index));
    }

    pub fn getEngineSprite(ship: ShipPartTileType) Sprite {
        var index: u16 = @intFromEnum(ship.rotation orelse .north);

        if (PartStats.isBroken(ship)) {
            index += 4;
        }

        return Sprite.init(ship_sheet, setRow(1, index));
    }

    pub fn getLaserSprite(ship: ShipPartTileType) Sprite {
        var index: u16 = 0;

        if (PartStats.isBroken(ship)) {
            index += 1;
        }

        return Sprite.init(ship_sheet, setRow(3, index));
    }

    pub fn getStorageSprite(ship: ShipPartTileType) Sprite {
        var index: u16 = 0;

        if (PartStats.isBroken(ship)) {
            index += 1;
        }

        return Sprite.init(ship_sheet, setRow(4, index));
    }

    pub fn getRailgunSprite(ship: ShipPartTileType) Sprite {
        var index: u16 = 0;

        if (PartStats.isBroken(ship)) {
            index += 1;
        }

        return Sprite.init(ship_sheet, setRow(5, index));
    }

    pub fn getSmartCoreSprite(ship: ShipPartTileType) Sprite {
        var index: u16 = 0;

        if (PartStats.isBroken(ship)) {
            index += 1;
        }

        return Sprite.init(ship_sheet, setRow(6, index));
    }

    pub fn getRadarSprite(ship: ShipPartTileType) Sprite {
        var index: u16 = 0;

        if (PartStats.isBroken(ship)) {
            index += 1;
        }

        return Sprite.init(ship_sheet, setRow(7, index));
    }
};
