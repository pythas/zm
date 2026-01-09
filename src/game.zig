const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");

const World = @import("world.zig").World;
const RailgunTrail = @import("effects.zig").RailgunTrail;
const InputManager = @import("input/input_manager.zig").InputManager;
const GameAction = @import("input/input_manager.zig").GameAction;
const Renderer = @import("renderer.zig").Renderer;
const GameplayRenderer = @import("renderer/gameplay_renderer.zig").GameplayRenderer;
const SpriteRenderer = @import("renderer/sprite_renderer.zig").SpriteRenderer;
const SpriteRenderData = @import("renderer/sprite_renderer.zig").SpriteRenderData;
const UiRect = @import("renderer/ui_renderer.zig").UiRect;
const UiVec4 = @import("renderer/ui_renderer.zig").UiVec4;
const ShipManagementUi = @import("ui/ship_management_ui.zig").ShipManagementUi;
const LineRenderData = @import("renderer/line_renderer.zig").LineRenderData;
const Vec2 = @import("vec2.zig").Vec2;
const PartStats = @import("ship.zig").PartStats;
const TileObject = @import("tile_object.zig").TileObject;
const InventoryLogic = @import("systems/inventory_logic.zig").InventoryLogic;
const PhysicsLogic = @import("systems/physics_logic.zig").PhysicsLogic;
const ShipLogic = @import("systems/ship_logic.zig").ShipLogic;

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
    gameplay_renderer: GameplayRenderer,
    ship_management: ShipManagementUi,

    input: InputManager,

    mode: GameMode = .in_world,
    world: World,

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        window: *zglfw.Window,
    ) !Self {
        const world = try World.init(allocator);
        const renderer = try Renderer.init(allocator, gctx, window);
        const gameplay_renderer = GameplayRenderer.init(allocator);
        const ship_management = ShipManagementUi.init(allocator, window);

        return .{
            .allocator = allocator,
            .window = window,
            .renderer = renderer,
            .gameplay_renderer = gameplay_renderer,
            .ship_management = ship_management,
            .world = world,
            .input = InputManager.init(window),
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
        const ship = &self.world.objects.items[0];

        self.input.update();

        if (self.input.isActionPressed(.toggle_inventory)) {
            if (self.mode == .in_world) {
                self.mode = .ship_management;
            } else {
                self.mode = .in_world;

                try PhysicsLogic.recalculatePhysics(ship, &self.world.physics);
                try InventoryLogic.initInventories(ship);
            }
        }

        if (self.input.isActionPressed(.select_action_1)) {
            self.world.player_controller.current_action = .mining;
        }

        if (self.input.isActionPressed(.select_action_2)) {
            self.world.player_controller.current_action = .laser;
        }

        if (self.input.isActionPressed(.select_action_5)) {
            self.world.player_controller.current_action = .railgun;
        }

        if (self.input.isActionPressed(.cheat_repair)) {
            self.world.research_manager.unlockAll();

            if (self.world.objects.items.len > 0) {
                ShipLogic.repairAll(ship);
                std.log.info("Game: CHEAT - Ship Repaired", .{});

                _ = try InventoryLogic.addItemToInventory(ship, .{ .resource = .iron }, 32, ship.position);
                _ = try InventoryLogic.addItemToInventory(ship, .{ .resource = .nickel }, 32, ship.position);
                _ = try InventoryLogic.addItemToInventory(ship, .{ .resource = .copper }, 32, ship.position);
                _ = try InventoryLogic.addItemToInventory(ship, .{ .resource = .carbon }, 32, ship.position);
                _ = try InventoryLogic.addItemToInventory(ship, .{ .resource = .gold }, 32, ship.position);
                _ = try InventoryLogic.addItemToInventory(ship, .{ .resource = .platinum }, 32, ship.position);
                _ = try InventoryLogic.addItemToInventory(ship, .{ .resource = .titanium }, 32, ship.position);
                _ = try InventoryLogic.addItemToInventory(ship, .{ .resource = .uranium }, 32, ship.position);

                try InventoryLogic.initInventories(ship);
            }
        }

        switch (self.mode) {
            .in_world => {
                try self.world.update(dt, &self.input);
                try self.ship_management.updateCrafting(dt, &self.world);

                self.renderer.global.write(self.window, &self.world, dt, t, self.mode);
            },
            .ship_management => {
                // update world with dummy inputs to keep simulation running
                var dummy_input = InputManager.init(self.window);
                try self.world.update(dt, &dummy_input);

                try self.ship_management.update(&self.renderer, &self.world, &self.input, dt, t);
            },
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

                const mouse_pos = self.input.mouse.getRelativePosition();
                const world_pos = world.camera.screenToWorld(mouse_pos);
                const ship = &self.world.objects.items[0];

                for (self.world.objects.items) |*obj| {
                    var hover_x: i32 = -1;
                    var hover_y: i32 = -1;
                    var highlight_all = false;

                    const is_mining = self.world.player_controller.current_action == .mining;
                    const is_precise = self.input.isActionDown(.mining_precise_target);

                    if (is_mining and is_precise) {
                        if (obj.getTileCoordsAtWorldPos(world_pos)) |coords| {
                            if (obj.id != ship.id and obj.object_type != .debris) {
                                const target_pos = obj.getTileWorldPos(coords.x, coords.y);
                                if (try self.world.player_controller.getMiningCandidate(ship, target_pos)) |_| {
                                    if (obj.getTile(coords.x, coords.y)) |tile| {
                                        if (tile.data != .empty) {
                                            hover_x = @intCast(coords.x);
                                            hover_y = @intCast(coords.y);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if (is_mining and !is_precise) {
                        if (obj.getTileCoordsAtWorldPos(world_pos)) |_| {
                            if (obj.id != ship.id and obj.object_type != .debris) {
                                highlight_all = true;
                            }
                        }
                    }

                    try self.renderer.sprite.prepareObject(obj);
                    try instances.append(SpriteRenderer.buildInstance(obj, hover_x, hover_y, highlight_all));
                }

                try self.renderer.sprite.writeInstances(instances.items);
                self.renderer.sprite.draw(pass, global, self.world.objects.items);

                try self.gameplay_renderer.drawLaserLines(pass, &self.world, &self.renderer, world_pos);
                try self.gameplay_renderer.drawRailgunTrails(pass, &self.world, &self.renderer);
                try self.gameplay_renderer.drawLaserBeams(pass, &self.world, &self.renderer);
                try self.gameplay_renderer.drawMiningBeams(pass, &self.world, &self.renderer);

                const thruster_count = try self.renderer.beam.writeThrusters(&self.world);
                self.renderer.beam.draw(pass, global, thruster_count);

                self.renderer.ui.beginFrame();

                const mouse_x = self.input.mouse.x;
                const mouse_y = self.input.mouse.y;
                const is_precise = self.input.isActionDown(.mining_precise_target);

                try self.gameplay_renderer.drawTooltips(&self.renderer, &self.world, world_pos, mouse_x, mouse_y, is_precise);

                const fb_size = self.window.getFramebufferSize();
                const screen_w: f32 = @floatFromInt(fb_size[0]);
                const screen_h: f32 = @floatFromInt(fb_size[1]);

                try self.gameplay_renderer.drawRadar(&self.renderer, &self.world, ship, screen_w, screen_h);

                try world.notifications.draw(&self.renderer.ui, screen_w, screen_h, self.renderer.font);
                try self.gameplay_renderer.drawActionBar(&self.renderer, &self.world, screen_w, screen_h);

                self.renderer.ui.flush(pass, global);
            },
            .ship_management => {
                try self.ship_management.draw(&self.renderer, &self.world, &self.input, pass);
            },
        }
    }
};
