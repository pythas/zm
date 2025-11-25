const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");

const World = @import("world.zig").World;
const Map = @import("map.zig").Map;
const KeyboardState = @import("input.zig").KeyboardState;
const Renderer = @import("renderer/renderer.zig").Renderer;
const SpriteRenderer = @import("renderer/sprite_renderer.zig").SpriteRenderer;
const SpriteRenderData = @import("renderer/sprite_renderer.zig").SpriteRenderData;
const tilemapWidth = @import("tile.zig").tilemapWidth;
const tilemapHeight = @import("tile.zig").tilemapHeight;
const scrollCallback = @import("world.zig").scrollCallback;

pub const GameMode = enum {
    InWorld,
    ShipEditor,
};

pub const Game = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    window: *zglfw.Window,
    renderer: Renderer,
    keyboard_state: KeyboardState,
    mode: GameMode = .InWorld,
    world: World,

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        window: *zglfw.Window,
        map: Map,
    ) !Self {
        const world = try World.init(allocator, map);
        const renderer = try Renderer.init(allocator, gctx, window);

        var self = Self{
            .allocator = allocator,
            .window = window,
            .renderer = renderer,
            .world = world,
            .keyboard_state = KeyboardState.init(window),
        };

        for (self.world.map.chunks.items) |*chunk| {
            try self.renderer.world.createChunkRenderData(chunk);
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.world.deinit();
    }

    pub fn setupCallbacks(self: *Self) void {
        self.window.setUserPointer(&self.world);
        _ = self.window.setScrollCallback(scrollCallback);
    }

    pub fn update(self: *Self, dt: f32, t: f32) !void {
        self.keyboard_state.beginFrame();

        if (self.keyboard_state.isPressed(.o)) {
            if (self.mode == .InWorld) {
                self.mode = .ShipEditor;
            } else {
                self.mode = .InWorld;
            }
        }

        self.renderer.global.write(self.window, &self.world, dt, t, self.mode);

        switch (self.mode) {
            .InWorld => {
                try self.world.update(dt, &self.keyboard_state, self.window);

                if (self.world.map.is_dirty) {
                    // TODO: only for dirty chunks
                    for (self.world.map.chunks.items) |*chunk| {
                        try self.renderer.world.createChunkRenderData(chunk);
                    }

                    self.world.map.is_dirty = false;
                }
            },
            .ShipEditor => {},
        }
    }

    pub fn render(
        self: *Self,
        pass: zgpu.wgpu.RenderPassEncoder,
    ) !void {
        switch (self.mode) {
            .InWorld => {
                const global = &self.renderer.global;
                const world = &self.world;

                try self.renderer.world.writeTextures(world);
                self.renderer.world.draw(pass, global, world);

                const instances = [_]SpriteRenderData{
                    SpriteRenderer.buildPlayerInstance(world),
                };
                try self.renderer.sprite.writeInstances(&instances);
                try self.renderer.sprite.writeTilemap(world.player.tiles);
                self.renderer.sprite.draw(pass, global);

                const beam_instance_count = try self.renderer.beam.writeBuffers(world);
                self.renderer.beam.draw(pass, global, beam_instance_count);
            },
            .ShipEditor => {
                const wh = self.window.getFramebufferSize();
                const screen_w: f32 = @floatFromInt(wh[0]);
                const screen_h: f32 = @floatFromInt(wh[1]);
                const mouse_pos = self.window.getCursorPos();
                const mouse_x: f32 = @floatCast(mouse_pos[0]);
                const mouse_y: f32 = @floatCast(mouse_pos[1]);

                const left_mouse_action = self.window.getMouseButton(.left);

                var ui = &self.renderer.ui;

                ui.beginFrame(.{ .x = mouse_x, .y = mouse_y }, left_mouse_action);

                // background
                try ui.panel(.{ .x = 0, .y = 0, .w = screen_w, .h = screen_h });

                // side panel
                try ui.panel(.{ .x = 10, .y = 10, .w = 200, .h = 300 });

                if (try ui.button(.{ .x = 20, .y = 20, .w = 180, .h = 32 }, "Hull")) {
                    std.debug.print("HULL\n", .{});
                }

                ui.endFrame(pass, &self.renderer.global);

                const global = &self.renderer.global;
                const world = &self.world;

                const instances = [_]SpriteRenderData{
                    .{
                        .wh = .{ tilemapWidth, tilemapHeight, 0, 0 },
                        .position = .{ tilemapWidth * 8 / 2, tilemapWidth * 8 / 2, 0, 0 },
                        .rotation = .{ 0, 0, 0, 0 },
                    },
                };
                try self.renderer.sprite.writeInstances(&instances);
                try self.renderer.sprite.writeTilemap(world.player.tiles);
                self.renderer.sprite.draw(pass, global);
            },
        }
    }
};
