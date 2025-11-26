const std = @import("std");

const Vec2 = @import("vec2.zig").Vec2;
const tile = @import("tile.zig");
const Tile = @import("tile.zig").Tile;
const TileReference = @import("tile.zig").TileReference;
const Map = @import("map.zig").Map;

pub const TileAction = struct {
    const Self = @This();

    pub const Kind = enum {
        Mine,
    };

    kind: Kind,
    tile_ref: TileReference,
    progress: f32,
    duration: f32,

    pub fn init(kind: Kind, tile_ref: TileReference, duration: f32) Self {
        return .{
            .kind = kind,
            .tile_ref = tile_ref,
            .progress = 0,
            .duration = duration,
        };
    }

    pub fn isActive(self: Self) bool {
        return self.progress < self.duration;
    }

    pub fn getProgress(self: Self) f32 {
        return @min(self.progress / self.duration, 1.0);
    }
};

pub const Player = struct {
    const Self = @This();
    pub const tileActionMineDuration = 10.0;

    position: Vec2,
    velocity: Vec2,

    rotation: f32,
    angular_velocity: f32,

    thrust: f32,
    torque: f32,

    velocity_damping: f32,
    angular_damping: f32,

    tiles: [tile.tilemapWidth][tile.tilemapHeight]Tile,

    tile_actions: std.ArrayList(TileAction),

    pub fn init(
        allocator: std.mem.Allocator,
        position: Vec2,
        rotation: f32,
        thrust: f32,
        torque: f32,
    ) Self {
        // const tiles: [playerWidth][playerHeight]Tile =
        //     .{.{Tile.init(.Hull, .Ships, 0)} ** playerHeight} ** playerWidth;

        var tiles: [tile.tilemapWidth][tile.tilemapHeight]Tile = undefined;

        // for (0..tile.tilemapHeight) |y| {
        //     for (0..tile.tilemapWidth) |x| {
        //         tiles[x][y] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        //     }
        // }

        tiles[0][0] = try Tile.init(allocator, .Hull, .Metal, .Ships, 0);
        tiles[1][0] = try Tile.init(allocator, .Hull, .Metal, .Ships, 33);
        tiles[2][0] = try Tile.init(allocator, .Hull, .Metal, .Ships, 33);
        tiles[3][0] = try Tile.init(allocator, .Hull, .Metal, .Ships, 1);
        tiles[0][1] = try Tile.init(allocator, .Hull, .Metal, .Ships, 32);
        tiles[0][2] = try Tile.init(allocator, .Hull, .Metal, .Ships, 32);
        tiles[0][3] = try Tile.init(allocator, .Hull, .Metal, .Ships, 32);
        tiles[0][4] = try Tile.init(allocator, .Hull, .Metal, .Ships, 32);
        tiles[0][5] = try Tile.init(allocator, .Hull, .Metal, .Ships, 32);
        tiles[0][6] = try Tile.init(allocator, .Hull, .Metal, .Ships, 32);
        tiles[1][1] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        tiles[1][2] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        tiles[1][3] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        tiles[1][4] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        tiles[1][5] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        tiles[1][6] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        tiles[2][1] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        tiles[2][2] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        tiles[2][3] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        tiles[2][4] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        tiles[2][5] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        tiles[2][6] = try Tile.init(allocator, .Hull, .Metal, .Ships, 36);
        tiles[3][1] = try Tile.init(allocator, .Hull, .Metal, .Ships, 34);
        tiles[3][2] = try Tile.init(allocator, .Hull, .Metal, .Ships, 34);
        tiles[3][3] = try Tile.init(allocator, .Hull, .Metal, .Ships, 34);
        tiles[3][4] = try Tile.init(allocator, .Hull, .Metal, .Ships, 34);
        tiles[3][5] = try Tile.init(allocator, .Hull, .Metal, .Ships, 34);
        tiles[3][6] = try Tile.init(allocator, .Hull, .Metal, .Ships, 34);
        tiles[0][6] = try Tile.init(allocator, .Hull, .Metal, .Ships, 2);
        tiles[1][6] = try Tile.init(allocator, .Hull, .Metal, .Ships, 35);
        tiles[2][6] = try Tile.init(allocator, .Hull, .Metal, .Ships, 35);
        tiles[3][6] = try Tile.init(allocator, .Hull, .Metal, .Ships, 3);

        return .{
            .position = position,
            .velocity = Vec2.init(0, 0),
            .rotation = rotation,
            .angular_velocity = 0,
            .thrust = thrust,
            .torque = torque,
            .velocity_damping = 0.1,
            .angular_damping = 0.9,
            .tiles = tiles,
            .tile_actions = std.ArrayList(TileAction).init(allocator),
        };
    }

    pub fn update(self: *Self, dt: f32, map: *Map) !void {
        // Movement
        self.position = self.position.add(self.velocity.mulScalar(dt));
        self.rotation = self.rotation + self.angular_velocity * dt;

        const v_factor = @max(0.0, 1.0 - self.velocity_damping * dt);
        const a_factor = @max(0.0, 1.0 - self.angular_damping * dt);

        self.velocity = self.velocity.mulScalar(v_factor);
        self.angular_velocity *= a_factor;

        // Actions
        var i: usize = self.tile_actions.items.len;
        while (i > 0) {
            i -= 1;

            var tile_action = &self.tile_actions.items[i];
            tile_action.progress += dt;

            if (!tile_action.isActive()) {
                switch (tile_action.kind) {
                    .Mine => {
                        std.debug.print("mine tile: {d} {d}\n", .{ tile_action.tile_ref.tile_x, tile_action.tile_ref.tile_y });
                        try tile_action.tile_ref.mineTile(map);
                    },
                }

                _ = self.tile_actions.orderedRemove(i);
            }
        }
    }

    // Movement
    pub fn applyThrust(self: *Self, dt: f32, input_thrust: f32) void {
        const direction = Vec2.init(-@sin(self.rotation), @cos(self.rotation));
        const acceleration = direction.mulScalar(input_thrust * self.thrust);

        self.velocity = self.velocity.add(acceleration.mulScalar(dt));
    }

    pub fn applyTorque(self: *Self, dt: f32, input_torque: f32) void {
        const acceleration = input_torque * self.torque;

        self.angular_velocity = self.angular_velocity + acceleration * dt;
    }

    pub fn applySideThrust(self: *Self, dt: f32, input_strafe: f32) void {
        const right = Vec2.init(@cos(self.rotation), @sin(self.rotation));

        const acceleration = right.mulScalar(input_strafe * self.thrust);
        self.velocity = self.velocity.add(acceleration.mulScalar(dt));
    }

    // Actions
    pub fn startTileAction(self: *Self, kind: TileAction.Kind, tile_ref: TileReference) !void {
        try self.tile_actions.append(TileAction.init(
            kind,
            tile_ref,
            tileActionMineDuration,
        ));
    }
};
