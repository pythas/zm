const std = @import("std");
const zgpu = @import("zgpu");
const zglfw = @import("zglfw");

const World = @import("../world.zig").World;
const Map = @import("../map.zig").Map;
const KeyboardState = @import("../input.zig").KeyboardState;
const GlobalRenderState = @import("../renderer.zig").GlobalRenderState;
const WorldRenderer = @import("../renderer.zig").WorldRenderer;
const SpriteRenderer = @import("../renderer.zig").SpriteRenderer;
const scrollCallback = @import("../world.zig").scrollCallback;

pub const GameMode = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    window: *zglfw.Window,
    global_render_state: GlobalRenderState,
    world_renderer: WorldRenderer,
    sprite_renderer: SpriteRenderer,
    keyboard_state: KeyboardState,
    world: World,

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        window: *zglfw.Window,
        map: Map,
    ) !Self {
        const world = try World.init(allocator, map);

        var self = Self{
            .allocator = allocator,
            .window = window,
            .world = world,
            .global_render_state = try GlobalRenderState.init(allocator, gctx),
            .world_renderer = undefined,
            .sprite_renderer = undefined,
            .keyboard_state = KeyboardState.init(window),
        };

        self.world_renderer = try WorldRenderer.init(allocator, gctx, window, &self.global_render_state);
        self.sprite_renderer = try SpriteRenderer.init(allocator, gctx, &self.global_render_state);
        try self.sprite_renderer.writeTilemap(&self.world);

        for (self.world.map.chunks.items) |*chunk| {
            try self.world_renderer.createChunkRenderData(chunk);
        }

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.world.deinit();
        self.world_renderer.deinit(self.allocator);
    }

    pub fn setupCallbacks(self: *Self) void {
        self.window.setUserPointer(&self.world);
        _ = self.window.setScrollCallback(scrollCallback);
    }

    pub fn update(self: *Self, dt: f32) !void {
        self.keyboard_state.beginFrame();
        self.world.update(dt, &self.keyboard_state, self.window);
    }

    pub fn render(
        self: *Self,
        pass: zgpu.wgpu.RenderPassEncoder,
        dt: f32,
        t: f32,
    ) !void {
        const renderer = self.world_renderer;
        const gctx = renderer.gctx;

        self.global_render_state.write(gctx, self.window, &self.world, dt, t);

        {
            try renderer.writeTextures(&self.world);

            const pipeline = gctx.lookupResource(renderer.pipeline).?;
            const bind_group = gctx.lookupResource(self.global_render_state.bind_group).?;

            pass.setPipeline(pipeline);
            pass.setBindGroup(0, bind_group, null);
        }

        // TODO: for each visible chunk
        for (self.world.map.chunks.items) |chunk| {
            const render_data = chunk.render_data orelse continue;
            const bind_group = gctx.lookupResource(render_data.bind_group).?;

            renderer.writeChunkBuffers(chunk);

            pass.setBindGroup(1, bind_group, null);
            pass.draw(6, 1, 0, 0);
        }

        try self.sprite_renderer.writeBuffers(&self.world);
        self.sprite_renderer.draw(pass, &self.global_render_state);
    }
};
