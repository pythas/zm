const std = @import("std");

const Sprite = @import("tile.zig").Sprite;
const SpriteSheet = @import("tile.zig").SpriteSheet;
const TileData = @import("tile.zig").TileData;
const BaseMaterial = @import("tile.zig").BaseMaterial;
const PartKind = @import("tile.zig").PartKind;
const TerrainTileType = @import("tile.zig").TerrainTileType;
const ShipPartTileType = @import("tile.zig").ShipPartTileType;

const row_width = 32;

const terrain_sheet: SpriteSheet = .terrain;
const ship_sheet: SpriteSheet = .ships;

fn setRow(row: u16, index: u16) u16 {
    return row * row_width + index;
}

pub const Assets = struct {
    pub fn getSprite(data: TileData, mask: u8) Sprite {
        return switch (data) {
            .empty => Sprite.initEmpty(),
            .terrain => |terrain| getTerrainSprite(terrain, mask),
            .ship_part => |ship| getShipPartSprite(ship, mask),
        };
    }

    pub fn getTerrainSprite(terrain: TerrainTileType, mask: u8) Sprite {
        return switch (terrain.base_material) {
            .rock => Sprite.init(terrain_sheet, mask),
            else => Sprite.init(terrain_sheet, 0),
        };
    }
    pub fn getShipPartSprite(ship: ShipPartTileType, mask: u8) Sprite {
        return switch (ship.kind) {
            .hull => getHullSprite(ship, mask),
            .reactor => getReactorSprite(ship),
            .engine => getEngineSprite(ship),
            .laser => getLaserSprite(ship),
            .cargo => getCargoSprite(ship),
            // else => Sprite.initEmpty(),
        };
    }

    pub fn getHullSprite(ship: ShipPartTileType, mask: u8) Sprite {
        _ = ship;
        return Sprite.init(ship_sheet, setRow(0, mask));
    }

    pub fn getReactorSprite(ship: ShipPartTileType) Sprite {
        var index = @intFromEnum(ship.rotation);

        if (ship.broken) {
            index += 1;
        }

        return Sprite.init(ship_sheet, setRow(2, index));
    }

    pub fn getEngineSprite(ship: ShipPartTileType) Sprite {
        var index = @intFromEnum(ship.rotation);

        if (ship.broken) {
            index += 4;
        }

        return Sprite.init(ship_sheet, setRow(1, index));
    }

    pub fn getLaserSprite(ship: ShipPartTileType) Sprite {
        var index = @intFromEnum(ship.rotation);

        if (ship.broken) {
            index += 1;
        }

        return Sprite.init(ship_sheet, setRow(3, index));
    }

    pub fn getCargoSprite(ship: ShipPartTileType) Sprite {
        var index = @intFromEnum(ship.rotation);

        if (ship.broken) {
            index += 1;
        }

        return Sprite.init(ship_sheet, setRow(4, index));
    }
};
