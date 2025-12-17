const std = @import("std");

const TileObject = @import("tile_object.zig").TileObject;
const Tile = @import("tile.zig").Tile;
const TileData = @import("tile.zig").TileData;
const PartKind = @import("tile.zig").PartKind;
const BaseMaterial = @import("tile.zig").BaseMaterial;
const Ore = @import("tile.zig").Ore;
const OreAmount = @import("tile.zig").OreAmount;
const Direction = @import("tile.zig").Direction;
const SpriteSheet = @import("tile.zig").SpriteSheet;
const Sprite = @import("tile.zig").Sprite;
const Vec2 = @import("vec2.zig").Vec2;

pub const ShipSerializationError = anyerror;

const JsonTileFlat = struct {
    x: usize,
    y: usize,
    data_type: []const u8,
    kind: ?[]const u8 = null,
    base_material: ?[]const u8 = null,
    rotation: []const u8,
};

const JsonShipData = struct {
    width: usize,
    height: usize,
    tiles: []JsonTileFlat,
};

pub fn saveShip(allocator: std.mem.Allocator, ship: TileObject, filename: []const u8) !void {
    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    var serializable_tiles = std.ArrayList(JsonTileFlat).init(allocator);
    defer serializable_tiles.deinit();

    for (0..ship.height) |y| {
        for (0..ship.width) |x| {
            const tile = ship.getTile(x, y) orelse continue;

            const data_type_str = @tagName(tile.data);
            var part_str: ?[]const u8 = null;
            var base_material_str: ?[]const u8 = null;

            switch (tile.data) {
                .ShipPart => |s| part_str = @tagName(s.kind),
                .Terrain => |t| base_material_str = @tagName(t.base_material),
                else => {},
            }

            try serializable_tiles.append(.{
                .x = x,
                .y = y,
                .data_type = data_type_str,
                .kind = part_str,
                .base_material = base_material_str,
                .rotation = @tagName(tile.rotation),
            });
        }
    }

    const serializable_ship = JsonShipData{
        .width = ship.width,
        .height = ship.height,
        .tiles = serializable_tiles.items,
    };

    try std.json.stringify(serializable_ship, .{ .whitespace = .indent_2 }, file.writer());
    std.debug.print("Ship saved to {s}\n", .{filename});
}

pub fn loadShip(
    allocator: std.mem.Allocator,
    id: u64,
    filename: []const u8,
) !TileObject {
    const file = std.fs.cwd().openFile(filename, .{}) catch |err| {
        return err;
    };
    defer file.close();

    const contents = file.readToEndAlloc(allocator, 1024 * 1024) catch |err| {
        return err;
    };
    defer allocator.free(contents);

    var parsed = std.json.parseFromSlice(JsonShipData, allocator, contents, .{}) catch |err| {
        return err;
    };
    defer parsed.deinit();

    const json_ship_data = parsed.value;

    var ship = try TileObject.init(
        allocator,
        id,
        json_ship_data.width,
        json_ship_data.height,
        Vec2.init(0, 0),
        0.0,
    );

    for (json_ship_data.tiles) |json_tile| {
        const data_tag = std.meta.stringToEnum(std.meta.Tag(TileData), json_tile.data_type) orelse return ShipSerializationError.InvalidEnumString;

        const tile_data: TileData = switch (data_tag) {
            .Empty => .Empty,
            .Terrain => blk: {
                const mat_str = json_tile.base_material orelse return ShipSerializationError.InvalidEnumString;
                const mat = std.meta.stringToEnum(BaseMaterial, mat_str) orelse return ShipSerializationError.InvalidEnumString;
                break :blk .{ .Terrain = .{ .base_material = mat, .ores = .{
                    .{ .ore = .None, .richness = 0 },
                    .{ .ore = .None, .richness = 0 },
                } } };
            },
            .ShipPart => blk: {
                const kind_str = json_tile.kind orelse return ShipSerializationError.InvalidEnumString;
                const kind = std.meta.stringToEnum(PartKind, kind_str) orelse return ShipSerializationError.InvalidEnumString;
                break :blk .{ .ShipPart = .{ .kind = kind, .tier = 1, .health = 100.0, .variation = 0 } };
            },
        };

        var new_tile = try Tile.init(tile_data);
        new_tile.rotation = std.meta.stringToEnum(Direction, json_tile.rotation) orelse return ShipSerializationError.InvalidEnumString;

        ship.setTile(json_tile.x, json_tile.y, new_tile);
    }

    std.debug.print("Ship loaded from {s}\n", .{filename});
    return ship;
}
