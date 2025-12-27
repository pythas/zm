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

                self.renderer.global.write(self.window, &self.world, dt, t, self.mode, 0.0, 0.0);
            },
            .ship_management => {
                self.ship_management.update(&self.renderer, &self.world, dt, t);
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

                var instances = std.ArrayList(SpriteRenderData).init(self.allocator);
                defer instances.deinit();

                for (self.world.objects.items) |*obj| {
                    try self.renderer.sprite.prepareObject(obj);
                    try instances.append(SpriteRenderer.buildInstance(obj));
                }

                try self.renderer.sprite.writeInstances(instances.items);
                self.renderer.sprite.draw(pass, global, self.world.objects.items);

                const beam_instance_count = try self.renderer.beam.writeBuffers(world);
                self.renderer.beam.draw(pass, global, beam_instance_count);

                // self.renderer.effect.draw(pass, global);

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
