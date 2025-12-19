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
const rng = @import("rng.zig");

const row_width = 32;

const terrain_sheet: SpriteSheet = .terrain;
const ship_sheet: SpriteSheet = .ships;
const resource_sheet: SpriteSheet = .resources;
const tool_sheet: SpriteSheet = .tools;

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

    pub fn getResourceSprite(resource: Resource) Sprite {
        if (resource == .none) {
            return Sprite.initEmpty();
        }

        const index = @intFromEnum(resource) - 1;

        return Sprite.init(resource_sheet, @intCast(index));
    }

    pub fn getToolSprite(tool: Tool) Sprite {
        const index = switch (tool) {
            .welding => 0,
        };

        return Sprite.init(tool_sheet, @intCast(index));
    }

    pub fn getTerrainSprite(terrain: TerrainTileType, mask: u8) Sprite {
        return switch (terrain.base_material) {
            .rock => getRockSprite(terrain, mask),
            else => Sprite.init(terrain_sheet, 0),
        };
    }

    pub fn getRockSprite(terrain: TerrainTileType, mask: u8) Sprite {
        const default = Sprite.init(terrain_sheet, setRow(0, mask));
        const most_common_resource = terrain.getMostCommonResource();

        if (most_common_resource == null) {
            return default;
        }

        var offset: u8 = 0;

        if (mask == 0b1111) {
            offset += rng.random().intRangeAtMost(u8, 0, 2);
        }

        return switch (most_common_resource.?) {
            .iron => Sprite.init(terrain_sheet, setRow(1, mask + offset)),
            else => default,
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
