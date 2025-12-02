const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");

const World = @import("world.zig").World;
const Map = @import("map.zig").Map;
const KeyboardState = @import("input.zig").KeyboardState;
const Renderer = @import("renderer/renderer.zig").Renderer;
const SpriteRenderer = @import("renderer/sprite_renderer.zig").SpriteRenderer;
const SpriteRenderData = @import("renderer/sprite_renderer.zig").SpriteRenderData;
const UiRect = @import("renderer/ui_renderer.zig").UiRect;
const Editor = @import("editor.zig").Editor;

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
    editor: Editor,
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
        const editor = Editor.init(allocator, window);

        var self = Self{
            .allocator = allocator,
            .window = window,
            .renderer = renderer,
            .editor = editor,
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
                self.world.player.recalculateStats();
                self.mode = .InWorld;
            }
        }

        switch (self.mode) {
            .InWorld => {
                self.renderer.global.write(self.window, &self.world, dt, t, self.mode, 0.0, 0.0);

                try self.world.update(dt, &self.keyboard_state, self.window);

                if (self.world.map.is_dirty) {
                    // TODO: only for dirty chunks
                    for (self.world.map.chunks.items) |*chunk| {
                        try self.renderer.world.createChunkRenderData(chunk);
                    }

                    self.world.map.is_dirty = false;
                }
            },
            .ShipEditor => {
                self.editor.update(&self.renderer, &self.world, dt, t);
            },
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
                try self.editor.draw(&self.renderer, &self.world, pass);
            },
        }
    }
};
