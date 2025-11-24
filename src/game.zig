const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");

const World = @import("world.zig").World;
const Map = @import("map.zig").Map;
const KeyboardState = @import("input.zig").KeyboardState;
const Renderer = @import("renderer/renderer.zig").Renderer;
const scrollCallback = @import("world.zig").scrollCallback;

pub const Game = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    window: *zglfw.Window,
    renderer: Renderer,
    keyboard_state: KeyboardState,
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

        try self.renderer.sprite.writeTilemap(&self.world);

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
        try self.world.update(dt, &self.keyboard_state, self.window);

        if (self.world.map.is_dirty) {
            // TODO: only for dirty chunks
            for (self.world.map.chunks.items) |*chunk| {
                try self.renderer.world.createChunkRenderData(chunk);
            }

            self.world.map.is_dirty = false;
        }

        self.renderer.update(self.window, &self.world, dt, t);
    }

    pub fn render(
        self: *Self,
        pass: zgpu.wgpu.RenderPassEncoder,
    ) !void {
        try self.renderer.draw(pass, &self.world);
    }
};
