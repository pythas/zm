const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");

const World = @import("world.zig").World;
const KeyboardState = @import("input.zig").KeyboardState;
const MouseState = @import("input.zig").MouseState;
const Renderer = @import("renderer.zig").Renderer;
const SpriteRenderer = @import("renderer/sprite_renderer.zig").SpriteRenderer;
const SpriteRenderData = @import("renderer/sprite_renderer.zig").SpriteRenderData;
const UiRect = @import("renderer/ui_renderer.zig").UiRect;
const ShipManagement = @import("ship_management.zig").ShipManagement;
const LineRenderData = @import("renderer/line_renderer.zig").LineRenderData;

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
                self.mode = .in_world;
            }
        }

        if (self.keyboard_state.isPressed(.f1)) {
            self.world.research_manager.unlockAll();
            if (self.world.objects.items.len > 0) {
                const ship = &self.world.objects.items[0];

                ship.repairAll();
                std.log.info("Game: CHEAT - Ship Repaired", .{});

                _ = try ship.addItemToInventory(.{ .resource = .iron }, 50, ship.position);
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

    fn drawLaserLines(self: *Self, pass: zgpu.wgpu.RenderPassEncoder, world_pos: @import("vec2.zig").Vec2) !void {
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

                    if (obj.getTileCoordsAtWorldPos(world_pos)) |coords| {
                        if (obj.id != ship.id and obj.object_type != .debris) {
                            const target_pos = obj.getTileWorldPos(coords.x, coords.y);
                            if (try world.player_controller.getLaserCandidate(ship, target_pos)) |_| {
                                if (obj.getTile(coords.x, coords.y)) |tile| {
                                    if (tile.data != .empty) {
                                        hover_x = @intCast(coords.x);
                                        hover_y = @intCast(coords.y);
                                    }
                                }
                            }
                        }
                    }

                    try self.renderer.sprite.prepareObject(obj);
                    try instances.append(SpriteRenderer.buildInstance(obj, hover_x, hover_y));
                }

                try self.renderer.sprite.writeInstances(instances.items);
                self.renderer.sprite.draw(pass, global, self.world.objects.items);

                // lines
                if (self.mode == .in_world) {
                    try self.drawLaserLines(pass, world_pos);
                }

                const beam_instance_count = try self.renderer.beam.writeBuffers(world);
                self.renderer.beam.draw(pass, global, beam_instance_count);

                self.renderer.ui.beginFrame();
                const fb_size = self.window.getFramebufferSize();
                try world.notifications.draw(&self.renderer.ui, @floatFromInt(fb_size[0]), self.renderer.font);
                self.renderer.ui.flush(pass, global);
            },
            .ship_management => {
                try self.ship_management.draw(&self.renderer, &self.world, pass);
            },
        }
    }
};
