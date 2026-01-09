const std = @import("std");
const zgpu = @import("zgpu");

const World = @import("../world.zig").World;
const Renderer = @import("../renderer.zig").Renderer;
const LineRenderData = @import("line_renderer.zig").LineRenderData;
const UiRect = @import("ui_renderer.zig").UiRect;
const UiVec4 = @import("ui_renderer.zig").UiVec4;
const PartStats = @import("../ship.zig").PartStats;
const TileObject = @import("../tile_object.zig").TileObject;
const Vec2 = @import("../vec2.zig").Vec2;
const config = @import("../config.zig");
const ResourceStats = @import("../resource.zig").ResourceStats;
const Resource = @import("../resource.zig").Resource;

pub const GameplayRenderer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
        };
    }

    pub fn drawRailgunTrails(self: *Self, pass: zgpu.wgpu.RenderPassEncoder, world: *World, renderer: *Renderer) !void {
        if (world.railgun_trails.items.len == 0) return;

        var lines = std.ArrayList(LineRenderData).init(self.allocator);
        defer lines.deinit();

        for (world.railgun_trails.items) |trail| {
            const alpha = trail.lifetime / trail.max_lifetime;
            try lines.append(.{
                .start = .{ trail.start.x, trail.start.y },
                .end = .{ trail.end.x, trail.end.y },
                .color = .{ 0.5, 0.9, 1.0, alpha },
                .thickness = 3.0 * alpha,
                .dash_scale = 0.0,
            });
        }

        renderer.line.draw(pass, &renderer.global, lines.items);
    }

    pub fn drawLaserBeams(self: *Self, pass: zgpu.wgpu.RenderPassEncoder, world: *World, renderer: *Renderer) !void {
        if (world.laser_beams.items.len == 0) return;

        var lines = std.ArrayList(LineRenderData).init(self.allocator);
        defer lines.deinit();

        for (world.laser_beams.items) |beam| {
            const alpha = beam.lifetime / beam.max_lifetime;
            try lines.append(.{
                .start = .{ beam.start.x, beam.start.y },
                .end = .{ beam.end.x, beam.end.y },
                .color = .{ beam.color[0], beam.color[1], beam.color[2], beam.color[3] * alpha },
                .thickness = 2.0,
                .dash_scale = 0.0,
            });
        }

        renderer.line.draw(pass, &renderer.global, lines.items);
    }

    pub fn drawMiningBeams(self: *Self, pass: zgpu.wgpu.RenderPassEncoder, world: *World, renderer: *Renderer) !void {
        if (world.player_controller.tile_actions.items.len == 0) return;

        var lines = std.ArrayList(LineRenderData).init(self.allocator);
        defer lines.deinit();

        const ship = &world.objects.items[0];

        for (world.player_controller.tile_actions.items) |action| {
            if (action.kind != .mine) continue;

            const source_pos = ship.getTileWorldPos(action.source.x, action.source.y);

            if (world.getObjectById(action.target.object_id)) |target_obj| {
                const target_pos = target_obj.getTileWorldPos(action.target.tile_x, action.target.tile_y);

                try lines.append(.{
                    .start = .{ source_pos.x, source_pos.y },
                    .end = .{ target_pos.x, target_pos.y },
                    .color = .{ 1.0, 0.6, 0.1, 0.7 }, // Amber/Orange
                    .thickness = 1.5,
                    .dash_scale = 0.0,
                });
            }
        }

        renderer.line.draw(pass, &renderer.global, lines.items);
    }

    pub fn drawLaserLines(self: *Self, pass: zgpu.wgpu.RenderPassEncoder, world: *World, renderer: *Renderer, world_pos: Vec2) !void {
        const action = world.player_controller.current_action;
        if (action != .laser and action != .mining) {
            return;
        }

        const ship = &world.objects.items[0];
        const PartKind = @import("../tile.zig").PartKind;
        const part_kind: PartKind = if (action == .mining) .mining_laser else .laser;
        const tile_refs = try ship.getTilesByPartKind(part_kind);
        defer self.allocator.free(tile_refs);

        if (tile_refs.len == 0) return;

        var lines = std.ArrayList(LineRenderData).init(self.allocator);
        defer lines.deinit();

        for (world.objects.items) |*obj| {
            if (obj.id == ship.id or obj.object_type == .debris) {
                continue;
            }

            if (obj.getTileCoordsAtWorldPos(world_pos)) |coords| {
                const target_pos = obj.getTileWorldPos(coords.x, coords.y);
                const tile = obj.getTile(coords.x, coords.y) orelse continue;

                if (tile.data == .empty) {
                    continue;
                }

                for (tile_refs) |tile_ref| {
                    // check if busy
                    var is_used = false;
                    for (world.player_controller.tile_actions.items) |tile_action| {
                        if (tile_action.source.x == tile_ref.tile_x and
                            tile_action.source.y == tile_ref.tile_y)
                        {
                            is_used = true;
                            break;
                        }
                    }
                    if (is_used) continue;

                    const laser_world_pos = ship.getTileWorldPos(tile_ref.tile_x, tile_ref.tile_y);
                    const ti = ship.getTile(tile_ref.tile_x, tile_ref.tile_y).?;
                    const part = ti.getShipPart().?;
                    const is_broken = PartStats.isBroken(part);
                    const range_sq = if (action == .mining)
                        PartStats.getMiningRangeSq(part.tier, is_broken)
                    else
                        PartStats.getLaserRangeSq(part.tier, is_broken);

                    const range = std.math.sqrt(range_sq);

                    const diff = target_pos.sub(laser_world_pos);
                    const dist = diff.length();
                    if (dist < 0.001) continue;
                    const dir = diff.normalize();

                    const limit_point = laser_world_pos.add(dir.mulScalar(range));

                    const seg1_end = if (dist < range) target_pos else limit_point;

                    try lines.append(.{
                        .start = .{ laser_world_pos.x, laser_world_pos.y },
                        .end = .{ seg1_end.x, seg1_end.y },
                        .color = .{ 1.0, 1.0, 1.0, 0.1 },
                        .thickness = 2.0,
                        .dash_scale = 0.0,
                    });

                    if (dist > range) {
                        try lines.append(.{
                            .start = .{ seg1_end.x, seg1_end.y },
                            .end = .{ target_pos.x, target_pos.y },
                            .color = .{ 1.0, 1.0, 1.0, 0.05 },
                            .thickness = 2.0,
                            .dash_scale = 0.0,
                        });
                    }
                }
                break;
            }
        }

        renderer.line.draw(pass, &renderer.global, lines.items);
    }

    pub fn drawRadar(self: *Self, renderer: *Renderer, world: *World, ship: *TileObject, screen_w: f32, screen_h: f32) !void {
        _ = self;
        _ = screen_h;

        const radar_refs = try ship.getTilesByPartKind(.radar);
        defer ship.allocator.free(radar_refs);

        if (radar_refs.len == 0) return;
        const radar = ship.getTile(radar_refs[0].tile_x, radar_refs[0].tile_y) orelse return;
        const radar_part = radar.getShipPart() orelse return;
        if (PartStats.isBroken(radar_part)) return;

        if (world.objects.items.len == 0) {
            return;
        }

        const range = config.ui.radar_range;
        const range_sq = range * range;

        const radar_size = config.ui.radar_size;
        const padding = config.ui.radar_padding;
        const radar_rect = UiRect{
            .x = screen_w - radar_size - padding,
            .y = padding,
            .w = radar_size,
            .h = radar_size,
        };

        const radar_center_x = radar_rect.x + radar_size / 2.0;
        const radar_center_y = radar_rect.y + radar_size / 2.0;
        const scale = (radar_size / 2.0) / range;

        const blip_size = config.ui.radar_blip_size;

        // background
        _ = try renderer.ui.panel(radar_rect, null, null);

        // objects
        for (world.objects.items) |*obj| {
            if (obj.id == ship.id) continue;
            if (obj.object_type == .debris) continue;

            const rel_pos = obj.position.sub(ship.position);
            const dist_sq = rel_pos.lengthSq();

            if (dist_sq > range_sq) continue;

            const blip_x = radar_center_x + rel_pos.x * scale;
            const blip_y = radar_center_y + rel_pos.y * scale;

            const color: UiVec4 = switch (obj.object_type) {
                .enemy_drone => .{ .r = 1.0, .g = 0.2, .b = 0.2, .a = 0.8 },
                else => .{ .r = 0.2, .g = 1.0, .b = 0.2, .a = 0.6 },
            };

            try renderer.ui.rectangle(.{
                .x = blip_x - blip_size / 2.0,
                .y = blip_y - blip_size / 2.0,
                .w = blip_size,
                .h = blip_size,
            }, color);
        }

        // player blip
        const player_blip_size = config.ui.radar_player_blip_size;
        try renderer.ui.rectangle(.{
            .x = radar_center_x - player_blip_size / 2.0,
            .y = radar_center_y - player_blip_size / 2.0,
            .w = player_blip_size,
            .h = player_blip_size,
        }, .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 });
    }

    pub fn drawActionBar(self: *Self, renderer: *Renderer, world: *World, screen_w: f32, screen_h: f32) !void {
        const style = &renderer.ui.style;
        const bar_h = style.action_button_height;
        const button_w = style.action_button_width;
        const spacing = style.action_button_spacing;

        const ship = &world.objects.items[0];
        const mining_tiles = try ship.getTilesByPartKind(.mining_laser);
        defer self.allocator.free(mining_tiles);
        const laser_tiles = try ship.getTilesByPartKind(.laser);
        defer self.allocator.free(laser_tiles);
        const railgun_tiles = try ship.getTilesByPartKind(.railgun);
        defer self.allocator.free(railgun_tiles);

        var count: usize = 0;
        if (mining_tiles.len > 0) count += 1;
        if (laser_tiles.len > 0) count += 1;
        if (railgun_tiles.len > 0) count += 1;

        if (count == 0) return;

        const total_w = @as(f32, @floatFromInt(count)) * button_w + @as(f32, @floatFromInt(count - 1)) * spacing;
        var current_x = (screen_w - total_w) / 2.0;
        const bar_y = screen_h - bar_h - 20.0;

        if (mining_tiles.len > 0) {
            const rect = UiRect{ .x = current_x, .y = bar_y, .w = button_w, .h = bar_h };
            const is_active = world.player_controller.current_action == .mining;
            const state = try renderer.ui.button(rect, is_active, false, "1. Mining", renderer.font);

            if (state.is_clicked) {
                world.player_controller.current_action = .mining;
            }

            current_x += button_w + spacing;
        }

        if (laser_tiles.len > 0) {
            const rect = UiRect{ .x = current_x, .y = bar_y, .w = button_w, .h = bar_h };
            const is_active = world.player_controller.current_action == .laser;
            const state = try renderer.ui.button(rect, is_active, false, "2. Laser", renderer.font);

            if (state.is_clicked) {
                world.player_controller.current_action = .laser;
            }

            current_x += button_w + spacing;
        }

        if (railgun_tiles.len > 0) {
            const rect = UiRect{ .x = current_x, .y = bar_y, .w = button_w, .h = bar_h };
            const is_active = world.player_controller.current_action == .railgun;
            const state = try renderer.ui.button(rect, is_active, false, "5. Railgun", renderer.font);

            if (state.is_clicked) {
                world.player_controller.current_action = .railgun;
            }

            current_x += button_w + spacing;
        }
    }

    pub fn drawTooltips(self: *Self, renderer: *Renderer, world: *World, world_pos: Vec2, mouse_x: f32, mouse_y: f32, is_precise: bool) !void {
        _ = self;
        const ship = &world.objects.items[0];

        for (world.objects.items) |*obj| {
            if (obj.id == ship.id or obj.object_type == .debris) continue;

            var hover_coords: ?struct { x: i32, y: i32 } = null;
            const is_mining = world.player_controller.current_action == .mining;

            if (is_mining and !is_precise) {
                if (obj.getTileCoordsAtWorldPos(world_pos)) |coords| {
                    hover_coords = .{ .x = @intCast(coords.x), .y = @intCast(coords.y) };
                }
            } else {
                // Inline getHoverCoords logic
                if (obj.getTileCoordsAtWorldPos(world_pos)) |coords| {
                    var valid_candidate = false;
                    if (is_mining) {
                        const target_pos = obj.getTileWorldPos(coords.x, coords.y);
                        if (try world.player_controller.getMiningCandidate(ship, target_pos)) |_| {
                            valid_candidate = true;
                        }
                    }

                    if (valid_candidate) {
                        if (obj.getTile(coords.x, coords.y)) |tile| {
                            if (tile.data != .empty) {
                                hover_coords = .{ .x = @intCast(coords.x), .y = @intCast(coords.y) };
                            }
                        }
                    }
                }
            }

            if (hover_coords) |coords| {
                if (obj.getTile(@intCast(coords.x), @intCast(coords.y))) |tile| {
                    if (tile.data != .empty) {
                        var buf: [512]u8 = undefined;
                        var stream = std.io.fixedBufferStream(&buf);
                        const writer = stream.writer();

                        if (tile.data == .terrain) {
                            if (is_precise) {
                                // Shift pressed: Show specific tile contents
                                const terrain = tile.data.terrain;
                                try writer.print("Tile Resources:", .{});
                                if (terrain.resources.len > 0) {
                                    for (terrain.resources.slice()) |res| {
                                        const name = ResourceStats.getName(res.resource);
                                        try writer.print("\n- {s}: {d}", .{ name, res.amount });
                                    }
                                } else {
                                    try writer.print("\n(Empty)", .{});
                                }
                            } else {
                                // Default: Show object composition
                                var total_mass: u32 = 0;
                                var counts = [_]u32{0} ** 9;

                                for (obj.tiles) |t| {
                                    if (t.data == .terrain) {
                                        for (t.data.terrain.resources.slice()) |res| {
                                            counts[@intFromEnum(res.resource)] += res.amount;
                                            total_mass += res.amount;
                                        }
                                    }
                                }

                                try writer.print("Asteroid Composition:", .{});
                                if (total_mass > 0) {
                                    const fields = @typeInfo(Resource).@"enum".fields;
                                    inline for (fields) |field| {
                                        const value = field.value;
                                        if (value != 0 and counts[value] > 0) { // Skip none
                                            const pct = @as(f32, @floatFromInt(counts[value])) / @as(f32, @floatFromInt(total_mass)) * 100.0;
                                            const name = ResourceStats.getName(@enumFromInt(value));
                                            try writer.print("\n- {s}: {d:.1}%", .{ name, pct });
                                        }
                                    }
                                } else {
                                    try writer.print("\n(Barren)", .{});
                                }
                            }
                        } else if (tile.data == .ship_part) {
                            const part = tile.data.ship_part;
                            try writer.print("Part: {s}", .{ @tagName(part.kind) });
                        }

                        const text = stream.getWritten();
                        if (text.len > 0) {
                            try renderer.ui.tooltip(mouse_x + 10, mouse_y + 10, text, renderer.font);
                        }
                        break;
                    }
                }
            }
        }
    }
};
