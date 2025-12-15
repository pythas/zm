const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");

const World = @import("world.zig").World;
const KeyboardState = @import("input.zig").KeyboardState;
const MouseState = @import("input.zig").MouseState;
const Renderer = @import("renderer/renderer.zig").Renderer;
const SpriteRenderer = @import("renderer/sprite_renderer.zig").SpriteRenderer;
const SpriteRenderData = @import("renderer/sprite_renderer.zig").SpriteRenderData;
const UiRect = @import("renderer/ui_renderer.zig").UiRect;
const Editor = @import("editor.zig").Editor;

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
    mouse_state: MouseState,

    mode: GameMode = .InWorld,
    world: World,

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        window: *zglfw.Window,
    ) !Self {
        const world = try World.init(allocator);
        const renderer = try Renderer.init(allocator, gctx, window);
        const editor = Editor.init(allocator, window);

        return .{
            .allocator = allocator,
            .window = window,
            .renderer = renderer,
            .editor = editor,
            .world = world,
            .keyboard_state = KeyboardState.init(window),
            .mouse_state = MouseState.init(window),
        };
    }

    pub fn deinit(self: *Self) void {
        self.world.deinit();
        self.renderer.deinit();
        self.editor.deinit();
    }

    pub fn setupCallbacks(self: *Self) void {
        self.window.setUserPointer(&self.world);
        _ = self.window.setScrollCallback(scrollCallback);
    }

    pub fn update(self: *Self, dt: f32, t: f32) !void {
        self.keyboard_state.update();
        self.mouse_state.update();

        if (self.keyboard_state.isPressed(.o)) {
            if (self.mode == .InWorld) {
                self.mode = .ShipEditor;
            } else {
                try self.world.objects.items[0].recalculatePhysics(&self.world.physics);
                self.mode = .InWorld;
            }
        }

        switch (self.mode) {
            .InWorld => {
                try self.world.update(dt, &self.keyboard_state, &self.mouse_state);

                self.renderer.global.write(self.window, &self.world, dt, t, self.mode, 0.0, 0.0);
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
            },
            .ShipEditor => {
                try self.editor.draw(&self.renderer, &self.world, pass);
            },
        }
    }
};
