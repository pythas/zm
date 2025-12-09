const std = @import("std");

const Vec2 = @import("vec2.zig").Vec2;
const Tile = @import("tile.zig").Tile;
const Direction = @import("tile.zig").Direction;
const Offset = @import("tile.zig").Offset;
const RigidBody = @import("rigid_body.zig").RigidBody;
const TileObject = @import("tile_object.zig").TileObject;
const KeyboardState = @import("input.zig").KeyboardState;

pub const PlayerController = struct {
    const Self = @This();
    pub const tileActionMineDuration = 3.0;

    target_index: usize,

    tile_actions: std.ArrayList(TileAction),

    pub fn init(allocator: std.mem.Allocator, target_index: usize) Self {
        return .{
            .target_index = target_index,
            .tile_actions = std.ArrayList(TileAction).init(allocator),
        };
    }

    pub fn update(
        self: *Self,
        dt: f32,
        objects: []TileObject,
        input: *const KeyboardState,
    ) void {
        if (self.target_index >= objects.len) {
            return;
        }

        var ship = &objects[self.target_index];

        if (input.isDown(.w)) {
            ship.applyInputThrust(dt, 1.0);
        }
        if (input.isDown(.s)) {
            ship.applyInputThrust(dt, -1.0);
        }

        if (input.isDown(.a)) {
            ship.applyTorque(dt, 1.0);
        }

        if (input.isDown(.d)) {
            ship.applyTorque(dt, -1.0);
        }

        if (input.isDown(.q)) {
            ship.applySideThrust(dt, -1.0);
        }

        if (input.isDown(.e)) {
            ship.applySideThrust(dt, 1.0);
        }

        // actions
        var i: usize = self.tile_actions.items.len;
        while (i > 0) {
            i -= 1;

            var tile_action = &self.tile_actions.items[i];
            tile_action.progress += dt;

            if (!tile_action.isActive()) {
                switch (tile_action.kind) {
                    .Mine => {
                        // std.debug.print("mine tile: {d} {d}\n", .{ tile_action.tile_ref.tile_x, tile_action.tile_ref.tile_y });
                        // try tile_action.tile_ref.mineTile(map);
                    },
                }

                _ = self.tile_actions.orderedRemove(i);
            }
        }
    }

    pub fn startTileAction(self: *Self, kind: TileAction.Kind) !void {
        _ = self;
        _ = kind;
        // try self.tile_actions.append(TileAction.init(
        //     kind,
        //     tileActionMineDuration,
        // ));
    }
};

pub const TileAction = struct {
    const Self = @This();

    pub const Kind = enum {
        Mine,
    };

    kind: Kind,
    progress: f32,
    duration: f32,

    pub fn init(kind: Kind, duration: f32) Self {
        return .{
            .kind = kind,
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
