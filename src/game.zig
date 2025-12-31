const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");

const World = @import("world.zig").World;
const RailgunTrail = @import("effects.zig").RailgunTrail;
const KeyboardState = @import("input.zig").KeyboardState;
const MouseState = @import("input.zig").MouseState;
const Renderer = @import("renderer.zig").Renderer;
const SpriteRenderer = @import("renderer/sprite_renderer.zig").SpriteRenderer;
const SpriteRenderData = @import("renderer/sprite_renderer.zig").SpriteRenderData;
const UiRect = @import("renderer/ui_renderer.zig").UiRect;
const UiVec4 = @import("renderer/ui_renderer.zig").UiVec4;
const ShipManagement = @import("ship_management.zig").ShipManagement;
const LineRenderData = @import("renderer/line_renderer.zig").LineRenderData;
const Vec2 = @import("vec2.zig").Vec2;

const scrollCallback = @import("world.zig").scrollCallback;

pub const GameMode = enum {
    in_world,
    ship_management,
};

pub const Game = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    window: *zglfw.Window,
    renderer: Renderer,
    ship_management: ShipManagement,

    keyboard_state: KeyboardState,
    mouse_state: MouseState,

    mode: GameMode = .in_world,
    world: World,

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        window: *zglfw.Window,
    ) !Self {
        const world = try World.init(allocator);
        const renderer = try Renderer.init(allocator, gctx, window);
        const ship_management = ShipManagement.init(allocator, window);

        return .{
            .allocator = allocator,
            .window = window,
            .renderer = renderer,
            .ship_management = ship_management,
            .world = world,
            .keyboard_state = KeyboardState.init(window),
            .mouse_state = MouseState.init(window),
        };
    }

    pub fn deinit(self: *Self) void {
        self.world.deinit();
        self.renderer.deinit();
        self.ship_management.deinit();
    }

    pub fn setupCallbacks(self: *Self) void {
        self.window.setUserPointer(&self.world);
        _ = self.window.setScrollCallback(scrollCallback);
    }

    pub fn update(self: *Self, dt: f32, t: f32) !void {
        self.keyboard_state.update();
        self.mouse_state.update();

        if (self.keyboard_state.isPressed(.o)) {
            if (self.mode == .in_world) {
                self.mode = .ship_management;
            } else {
                try self.world.objects.items[0].recalculatePhysics(&self.world.physics);
                try self.world.objects.items[0].initInventories();
                self.mode = .in_world;
            }
        }

        if (self.keyboard_state.isPressed(.one)) {
            self.world.player_controller.current_action = .laser;
        }

        if (self.keyboard_state.isPressed(.five)) {
            self.world.player_controller.current_action = .railgun;
        }

        if (self.keyboard_state.isPressed(.f1)) {
            self.world.research_manager.unlockAll();
            if (self.world.objects.items.len > 0) {
                const ship = &self.world.objects.items[0];

                ship.repairAll();
                std.log.info("Game: CHEAT - Ship Repaired", .{});

                _ = try ship.addItemToInventory(.{ .resource = .iron }, 32, ship.position);
            }
        }

        switch (self.mode) {
            .in_world => {
                try self.world.update(dt, &self.keyboard_state, &self.mouse_state);

                self.renderer.global.write(self.window, &self.world, dt, t, self.mode);
            },
            .ship_management => {
                self.ship_management.update(&self.renderer, &self.world, dt, t);
            },
        }
    }

    fn drawRailgunTrails(self: *Self, pass: zgpu.wgpu.RenderPassEncoder) !void {
        if (self.world.railgun_trails.items.len == 0) return;

        var lines = std.ArrayList(LineRenderData).init(self.allocator);
        defer lines.deinit();

        for (self.world.railgun_trails.items) |trail| {
            const alpha = trail.lifetime / trail.max_lifetime;
            try lines.append(.{
                .start = .{ trail.start.x, trail.start.y },
                .end = .{ trail.end.x, trail.end.y },
                .color = .{ 0.5, 0.9, 1.0, alpha },
                .thickness = 3.0 * alpha,
                .dash_scale = 0.0,
            });
        }

        self.renderer.line.draw(pass, &self.renderer.global, lines.items);
    }

    fn drawLaserBeams(self: *Self, pass: zgpu.wgpu.RenderPassEncoder) !void {
        if (self.world.laser_beams.items.len == 0) return;

        var lines = std.ArrayList(LineRenderData).init(self.allocator);
        defer lines.deinit();

        for (self.world.laser_beams.items) |beam| {
            const alpha = beam.lifetime / beam.max_lifetime;
            try lines.append(.{
                .start = .{ beam.start.x, beam.start.y },
                .end = .{ beam.end.x, beam.end.y },
                .color = .{ beam.color[0], beam.color[1], beam.color[2], beam.color[3] * alpha },
                .thickness = 2.0,
                .dash_scale = 0.0,
            });
        }

        self.renderer.line.draw(pass, &self.renderer.global, lines.items);
    }

    fn drawLaserLines(self: *Self, pass: zgpu.wgpu.RenderPassEncoder, world_pos: @import("vec2.zig").Vec2) !void {
        if (self.world.player_controller.current_action != .laser) {
            return;
        }

        var lines = std.ArrayList(LineRenderData).init(self.allocator);
        defer lines.deinit();

        const ship = &self.world.objects.items[0];

        for (self.world.objects.items) |*obj| {
            if (obj.id == ship.id or obj.object_type == .debris) {
                continue;
            }

            if (obj.getTileCoordsAtWorldPos(world_pos)) |coords| {
                const target_pos = obj.getTileWorldPos(coords.x, coords.y);
                const tile = obj.getTile(coords.x, coords.y) orelse continue;

                if (tile.data == .empty) {
                    continue;
                }

                const tile_refs = try ship.getTilesByPartKind(.laser);
                defer self.allocator.free(tile_refs);

                for (tile_refs) |tile_ref| {
                    // check if busy
                    var is_used = false;
                    for (self.world.player_controller.tile_actions.items) |tile_action| {
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
                    const sp = ti.getShipPart().?;
                    const is_broken = @import("ship.zig").PartStats.isBroken(sp);
                    const range_sq = @import("ship.zig").PartStats.getLaserRangeSq(sp.tier, is_broken);
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

        self.renderer.line.draw(pass, &self.renderer.global, lines.items);
    }

    fn drawRadar(self: *Self, screen_w: f32, screen_h: f32) !void {
        _ = screen_h;

        if (self.world.objects.items.len == 0) {
            return;
        }

        const ship = &self.world.objects.items[0];
        const range = 2000.0;
        const range_sq = range * range;

        const radar_size = 200.0;
        const padding = 20.0;
        const radar_rect = UiRect{
            .x = screen_w - radar_size - padding,
            .y = padding,
            .w = radar_size,
            .h = radar_size,
        };

        const radar_center_x = radar_rect.x + radar_size / 2.0;
        const radar_center_y = radar_rect.y + radar_size / 2.0;
        const scale = (radar_size / 2.0) / range;

        const blip_size = 2.0;

        // background
        _ = try self.renderer.ui.panel(radar_rect, null, null);

        // objects
        for (self.world.objects.items) |*obj| {
            if (obj.id == ship.id) continue;
            if (obj.object_type == .debris) continue;

            const rel_pos = obj.position.sub(ship.position);
            const dist_sq = rel_pos.lengthSq();

            if (dist_sq > range_sq) continue;

            const blip_x = radar_center_x + rel_pos.x * scale;
            const blip_y = radar_center_y + rel_pos.y * scale;

            const color: UiVec4 = switch (obj.object_type) {
                .enemy_drone => .{ .r = 1.0, .g = 0.2, .b = 0.2, .a = 1.0 },
                else => .{ .r = 0.2, .g = 1.0, .b = 0.2, .a = 0.8 },
            };

            try self.renderer.ui.rectangle(.{
                .x = blip_x - blip_size / 2.0,
                .y = blip_y - blip_size / 2.0,
                .w = blip_size,
                .h = blip_size,
            }, color);
        }

        // player blip
        try self.renderer.ui.rectangle(.{
            .x = radar_center_x - 1.5,
            .y = radar_center_y - 1.5,
            .w = 3.0,
            .h = 3.0,
        }, .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 });
    }

    fn getHoverCoords(self: *Self, obj: *@import("tile_object.zig").TileObject, world_pos: @import("vec2.zig").Vec2, ship: *@import("tile_object.zig").TileObject) !?struct { x: i32, y: i32 } {
        if (obj.getTileCoordsAtWorldPos(world_pos)) |coords| {
            if (obj.id != ship.id and obj.object_type != .debris) {
                var valid_candidate = false;
                if (self.world.player_controller.current_action == .laser) {
                    const target_pos = obj.getTileWorldPos(coords.x, coords.y);
                    if (try self.world.player_controller.getLaserCandidate(ship, target_pos)) |_| {
                        valid_candidate = true;
                    }
                }

                if (valid_candidate) {
                    if (obj.getTile(coords.x, coords.y)) |tile| {
                        if (tile.data != .empty) {
                            return .{ .x = @intCast(coords.x), .y = @intCast(coords.y) };
                        }
                    }
                }
            }
        }
        return null;
    }

    fn renderActionBar(self: *Self, screen_w: f32, screen_h: f32) !void {
        const style = &self.renderer.ui.style;
        const bar_h = style.action_button_height;
        const button_w = style.action_button_width;
        const spacing = style.action_button_spacing;

        const ship = &self.world.objects.items[0];
        const laser_tiles = try ship.getTilesByPartKind(.laser);
        defer self.allocator.free(laser_tiles);
        const railgun_tiles = try ship.getTilesByPartKind(.railgun);
        defer self.allocator.free(railgun_tiles);

        var count: usize = 0;
        if (laser_tiles.len > 0) count += 1;
        if (railgun_tiles.len > 0) count += 1;

        if (count == 0) return;

        const total_w = @as(f32, @floatFromInt(count)) * button_w + @as(f32, @floatFromInt(count - 1)) * spacing;
        var current_x = (screen_w - total_w) / 2.0;
        const bar_y = screen_h - bar_h - 20.0;

        if (laser_tiles.len > 0) {
            const rect = UiRect{ .x = current_x, .y = bar_y, .w = button_w, .h = bar_h };
            const is_active = self.world.player_controller.current_action == .laser;
            const state = try self.renderer.ui.button(rect, is_active, false, "1. Laser", self.renderer.font);

            if (state.is_clicked) {
                self.world.player_controller.current_action = .laser;
            }

            current_x += button_w + spacing;
        }

        if (railgun_tiles.len > 0) {
            const rect = UiRect{ .x = current_x, .y = bar_y, .w = button_w, .h = bar_h };
            const is_active = self.world.player_controller.current_action == .railgun;
            const state = try self.renderer.ui.button(rect, is_active, false, "5. Railgun", self.renderer.font);

            if (state.is_clicked) {
                self.world.player_controller.current_action = .railgun;
            }

            current_x += button_w + spacing;
        }
    }

    pub fn render(
        self: *Self,
        pass: zgpu.wgpu.RenderPassEncoder,
    ) !void {
        switch (self.mode) {
            .in_world => {
                const global = &self.renderer.global;
                const world = &self.world;

                self.renderer.background.draw(pass, global);

                var instances = std.ArrayList(SpriteRenderData).init(self.allocator);
                defer instances.deinit();

                const mouse_pos = self.mouse_state.getRelativePosition();
                const world_pos = world.camera.screenToWorld(mouse_pos);
                const ship = &self.world.objects.items[0];

                for (self.world.objects.items) |*obj| {
                    var hover_x: i32 = -1;
                    var hover_y: i32 = -1;

                    if (try self.getHoverCoords(obj, world_pos, ship)) |coords| {
                        hover_x = coords.x;
                        hover_y = coords.y;
                    }

                    try self.renderer.sprite.prepareObject(obj);
                    try instances.append(SpriteRenderer.buildInstance(obj, hover_x, hover_y));
                }

                try self.renderer.sprite.writeInstances(instances.items);
                self.renderer.sprite.draw(pass, global, self.world.objects.items);

                try self.drawLaserLines(pass, world_pos);
                try self.drawRailgunTrails(pass);
                try self.drawLaserBeams(pass);

                self.renderer.ui.beginFrame();

                const fb_size = self.window.getFramebufferSize();
                const screen_w: f32 = @floatFromInt(fb_size[0]);
                const screen_h: f32 = @floatFromInt(fb_size[1]);

                try self.drawRadar(screen_w, screen_h);

                try world.notifications.draw(&self.renderer.ui, screen_w, self.renderer.font);
                try self.renderActionBar(screen_w, screen_h);

                self.renderer.ui.flush(pass, global);
            },
            .ship_management => {
                try self.ship_management.draw(&self.renderer, &self.world, pass);
            },
        }
    }
};
