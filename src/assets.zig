const std = @import("std");

const Sprite = @import("tile.zig").Sprite;
const SpriteSheet = @import("tile.zig").SpriteSheet;
const TileData = @import("tile.zig").TileData;
const BaseMaterial = @import("tile.zig").BaseMaterial;
const PartKind = @import("tile.zig").PartKind;

const terrain_sheet: SpriteSheet = .Terrain;
const ship_sheet: SpriteSheet = .Ships;

pub const Assets = struct {
    pub fn getSprite(data: TileData, mask: u8) Sprite {
        return switch (data) {
            .Empty => Sprite.initEmpty(),
            .Terrain => |terrain| getTerrainSprite(terrain.base_material, mask),
            .ShipPart => |ship| getShipPartSprite(ship.kind, ship.tier, mask),
        };
    }

    pub fn getTerrainSprite(base_material: BaseMaterial, mask: u8) Sprite {
        return switch (base_material) {
            .Rock => Sprite.init(terrain_sheet, mask),
            else => Sprite.init(terrain_sheet, 0),
        };
    }
    pub fn getShipPartSprite(kind: PartKind, tier: u8, mask: u8) Sprite {
        return switch (kind) {
            .Hull => getHullSprite(tier, mask),
            else => Sprite.initEmpty(),
        };
    }

    pub fn getHullSprite(tier: u8, mask: u8) Sprite {
        _ = tier;
        _ = mask;
        return Sprite.init(ship_sheet, 36);
    }
};
