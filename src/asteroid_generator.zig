const std = @import("std");

const Vec2 = @import("vec2.zig").Vec2;
const Tile = @import("tile.zig").Tile;
const TileObject = @import("tile_object.zig").TileObject;
const ResourceAmount = @import("tile.zig").ResourceAmount;
const Resource = @import("resource.zig").Resource;

pub const AsteroidGenerator = struct {
    pub const Shape = enum {
        circle,
        rectangle,
        irregular,
    };

    pub const ResourceConfig = struct {
        resource: Resource,
        probability: f32,
        min_amount: u8,
        max_amount: u8,
    };

    pub fn createAsteroid(
        allocator: std.mem.Allocator,
        id: u64,
        position: Vec2,
        width: usize,
        height: usize,
        shape: Shape,
        variant: u8,
        resources: []const ResourceConfig,
    ) !TileObject {
        var asteroid = try TileObject.init(
            allocator,
            id,
            width,
            height,
            position,
            0,
        );
        asteroid.object_type = .asteroid;

        const center_x = @as(f32, @floatFromInt(width)) / 2.0;
        const center_y = @as(f32, @floatFromInt(height)) / 2.0;
        const radius_base = @min(center_x, center_y);

        var prng = std.Random.DefaultPrng.init(id);
        const rand = prng.random();

        for (0..height) |y| {
            for (0..width) |x| {
                var should_fill = false;

                const fx = @as(f32, @floatFromInt(x));
                const fy = @as(f32, @floatFromInt(y));
                const dx = fx - center_x + 0.5;
                const dy = fy - center_y + 0.5;

                switch (shape) {
                    .rectangle => should_fill = true,
                    .circle => {
                        const dist_sq = dx * dx + dy * dy;
                        if (dist_sq <= radius_base * radius_base) {
                            should_fill = true;
                        }
                    },
                    .irregular => {
                        const angle = std.math.atan2(dy, dx);
                        const dist = @sqrt(dx * dx + dy * dy);

                        const phase = @as(f32, @floatFromInt(id % 100));
                        const noise = (@sin(angle * 3.0 + phase) + @sin(angle * 7.0 - phase) * 0.5) * (radius_base * 0.2);
                        const radius = (radius_base * 0.8) + noise;

                        if (dist <= radius) {
                            should_fill = true;
                        }
                    },
                }

                if (should_fill) {
                    var tile_resources = try std.BoundedArray(ResourceAmount, 4).init(0);

                    for (resources) |res_config| {
                        if (rand.float(f32) < res_config.probability) {
                            if (tile_resources.len < 4) {
                                const range = res_config.max_amount - res_config.min_amount;
                                const amount = res_config.min_amount + rand.uintAtMost(u8, range);

                                tile_resources.appendAssumeCapacity(.{
                                    .resource = res_config.resource,
                                    .amount = amount,
                                });
                            }
                        }
                    }

                    asteroid.tiles[y * width + x] = try Tile.init(
                        .{
                            .terrain = .{
                                .base_material = .rock,
                                .variant = variant,
                                .resources = tile_resources,
                            },
                        },
                    );
                } else {
                    asteroid.tiles[y * width + x] = try Tile.initEmpty();
                }
            }
        }
        return asteroid;
    }
};
