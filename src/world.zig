const std = @import("std");
const color = @import("color.zig");
const math = std.math;
const zglfw = @import("zglfw");

const KeyboardState = @import("input.zig").KeyboardState;
const Map = @import("map.zig").Map;
const TileReference = @import("tile.zig").TileReference;
const Chunk = @import("map.zig").Chunk;
const Player = @import("player.zig").Player;
const Camera = @import("camera.zig").Camera;
const Ship = @import("ship.zig").Ship;
const Vec2 = @import("vec2.zig").Vec2;
const Tile = @import("tile.zig").Tile;

const tileSize = @import("tile.zig").tileSize;
const chunkSize = @import("chunk.zig").chunkSize;
const chunkPixelSize = @import("chunk.zig").chunkPixelSize;

pub const World = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    map: Map,
    camera: Camera,
    player: Player,

    last_left: zglfw.Action = .release,
    last_right: zglfw.Action = .release,

    pub fn init(allocator: std.mem.Allocator, map: Map) !Self {
        const camera = Camera.init(
            Vec2.init(0, 0),
        );

        const player = Player.init(
            allocator,
            Vec2.init(0, 0),
            0 * std.math.pi / 180.0,
        );

        return .{
            .allocator = allocator,
            .map = map,
            .camera = camera,
            .player = player,
        };
    }

    pub fn deinit(self: Self) void {
        _ = self;
    }

    pub fn update(
        self: *Self,
        dt: f32,
        keyboard_state: *const KeyboardState,
        window: *zglfw.Window,
    ) !void {
        const wh = window.getFramebufferSize();
        const mouse_pos = window.getCursorPos();
        const mouse_x: f32 = @floatCast(mouse_pos[0]);
        const mouse_y: f32 = @floatCast(mouse_pos[1]);
        const mouse_x_relative = mouse_x - @as(f32, @floatFromInt(wh[0])) / 2;
        const mouse_y_relative = mouse_y - @as(f32, @floatFromInt(wh[1])) / 2;

        const left_now = window.getMouseButton(.left);
        const right_now = window.getMouseButton(.right);

        const left_clicked = (left_now == .press and self.last_left == .release);
        const right_clicked = (right_now == .press and self.last_right == .release);

        if (keyboard_state.isDown(.w)) {
            self.player.applyInputThrust(dt, 1.0);
        }

        if (keyboard_state.isDown(.s)) {
            self.player.applyInputThrust(dt, -1.0);
        }

        if (keyboard_state.isDown(.a)) {
            self.player.applyTorque(dt, 1.0);
        }

        if (keyboard_state.isDown(.d)) {
            self.player.applyTorque(dt, -1.0);
        }

        if (keyboard_state.isDown(.q)) {
            self.player.applySideThrust(dt, -1.0);
        }

        if (keyboard_state.isDown(.e)) {
            self.player.applySideThrust(dt, 1.0);
        }

        if (left_clicked) {
            if (self.getTile(mouse_x_relative, mouse_y_relative)) |tile_ref| {
                if (tile_ref.getTile(&self.map)) |tile| {
                    if (tile.category != .Empty) {
                        try self.player.startTileAction(.Mine, tile_ref);
                    }
                }
            }
        }

        if (right_clicked) {
            // ...
        }

        // sync camera with player
        self.camera.position = self.player.body.position;

        try self.player.update(dt, &self.map);

        self.last_left = left_now;
        self.last_right = right_now;

        // meh
        self.collisions();
    }

    fn tryMovePlayer(self: *Self, x: f32, y: f32) void {
        self.player.position.x += x;
        self.player.position.y += y;
    }

    pub fn onScroll(self: *Self, xoffset: f64, yoffset: f64) void {
        _ = xoffset;

        if (yoffset > 0) {
            self.camera.zoom *= 1.1;
        } else if (yoffset < 0) {
            self.camera.zoom *= 0.9;
        }

        self.camera.zoom = @max(0.1, @min(10.0, self.camera.zoom));
    }

    fn getTile(self: *Self, local_x: f32, local_y: f32) ?TileReference {
        const world = self.camera.screenToWorld(
            .{
                .x = local_x,
                .y = local_y,
            },
        );

        return self.map.getTileAtWorld(world);
    }

    fn collisions(self: *Self) void {
        const pos = self.player.body.position.mulScalar(tileSize);
        const chunk_ref = self.map.getChunkAtWorld(pos) orelse return;

        const chunk = chunk_ref.getChunk(&self.map) orelse return;
        const chunk_size: f32 = @floatFromInt(chunkPixelSize);
        const tile_size: f32 = @floatFromInt(tileSize);
        const player_size: f32 = tile_size * 16.0;

        const tile_radius = tile_size / @sqrt(2.0);
        const player_radius = player_size / @sqrt(2.0);
        const combined_radius = tile_radius + player_radius;

        for (0..chunkSize) |x| {
            for (0..chunkSize) |y| {
                if (chunk.tiles[x][y].category == .Empty) {
                    continue;
                }

                const tile_x: f32 = @floatFromInt(x);
                const tile_y: f32 = @floatFromInt(y);

                const chunk_x: f32 = @floatFromInt(chunk.x);
                const chunk_y: f32 = @floatFromInt(chunk.y);

                const tile_world_x = chunk_x * chunk_size - chunk_size / 2 + tile_x * tile_size + tile_size / 2;
                const tile_world_y = chunk_y * chunk_size - chunk_size / 2 + tile_y * tile_size + tile_size / 2;
                const dx = pos.x - tile_world_x;
                const dy = pos.y - tile_world_y;
                const d = dx * dx + dy * dy;

                if (d < combined_radius * combined_radius) {
                    std.debug.print("{d}\n", .{d});
                }
            }
        }
    }
};

pub fn scrollCallback(window: *zglfw.Window, xoffset: f64, yoffset: f64) callconv(.c) void {
    const world = zglfw.getWindowUserPointer(window, World) orelse return;

    world.onScroll(xoffset, yoffset);
}
