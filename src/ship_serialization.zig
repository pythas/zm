const std = @import("std");
const TileObject = @import("tile_object.zig").TileObject;
const Tile = @import("tile.zig").Tile;
const Direction = @import("tile.zig").Direction;
const Category = @import("tile.zig").Category;
const BaseMaterial = @import("tile.zig").BaseMaterial;
const SpriteSheet = @import("tile.zig").SpriteSheet;
const Vec2 = @import("vec2.zig").Vec2;

const TileData = struct {
    x: usize,
    y: usize,
    category: u8,
    sprite: u16,
    rotation: u8,
};

const ShipData = struct {
    width: usize,
    height: usize,
    position: struct { x: f32, y: f32 },
    rotation: f32,
    tiles: []TileData,
};

pub fn saveShip(allocator: std.mem.Allocator, ship: TileObject, filename: []const u8) !void {
    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    var tiles_data = std.ArrayList(TileData).init(allocator);
    defer tiles_data.deinit();

    for (0..ship.height) |y| {
        for (0..ship.width) |x| {
            const tile = ship.getTile(x, y) orelse continue;
            if (tile.category != .Empty) {
                try tiles_data.append(.{
                    .x = x,
                    .y = y,
                    .category = @intFromEnum(tile.category),
                    .sprite = tile.sprite,
                    .rotation = @intFromEnum(tile.rotation),
                });
            }
        }
    }

    const ship_data = ShipData{
        .width = ship.width,
        .height = ship.height,
        .position = .{ .x = ship.position.x, .y = ship.position.y },
        .rotation = ship.rotation,
        .tiles = tiles_data.items,
    };

    try std.json.stringify(ship_data, .{ .whitespace = .indent_2 }, file.writer());
    std.debug.print("Ship saved to {s}\n", .{filename});
}

pub fn loadShip(allocator: std.mem.Allocator, filename: []const u8) !TileObject {
    const file = std.fs.cwd().openFile(filename, .{}) catch |err| {
        std.debug.print("Failed to open {s}: {}\n", .{ filename, err });
        return err;
    };
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(contents);

    var parsed = try std.json.parseFromSlice(ShipData, allocator, contents, .{});
    defer parsed.deinit();

    const ship_data = parsed.value;

    var ship = try TileObject.init(
        allocator,
        ship_data.width,
        ship_data.height,
        Vec2{ .x = ship_data.position.x, .y = ship_data.position.y },
        ship_data.rotation,
    );

    // Load tiles
    for (ship_data.tiles) |tile_data| {
        const category: Category = @enumFromInt(tile_data.category);
        const rotation: Direction = @enumFromInt(tile_data.rotation);

        const tile = try Tile.init(
            allocator,
            category,
            .Metal, // Default material
            .Ships, // Default sheet
            tile_data.sprite,
        );
        
        var loaded_tile = tile;
        loaded_tile.rotation = rotation;
        
        ship.setTile(tile_data.x, tile_data.y, loaded_tile);
    }

    std.debug.print("Ship loaded from {s}\n", .{filename});
    return ship;
}