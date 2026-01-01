const std = @import("std");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const zglfw = @import("zglfw");
const shader_utils = @import("../shader_utils.zig");

const MouseState = @import("../input.zig").MouseState;
const World = @import("../world.zig").World;
const Tile = @import("../tile.zig").Tile;
const Sprite = @import("../tile.zig").Sprite;
const Texture = @import("../texture.zig").Texture;
const Assets = @import("../assets.zig").Assets;
const GlobalRenderState = @import("common.zig").GlobalRenderState;
const packTileForGpu = @import("common.zig").packTileForGpu;
const packSpriteForGpu = @import("common.zig").packSpriteForGpu;
const Item = @import("../inventory.zig").Item;
const Font = @import("font.zig").Font;

const UiVertex = struct {
    position: UiVec2,
    uv: UiVec2,
    color: UiVec4,
    data: u32,
    mode: u32,
};

pub const UiVec2 = struct {
    x: f32,
    y: f32,
};

pub const UiVec4 = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

pub const UiRect = struct {
    const Self = @This();

    x: f32,
    y: f32,
    w: f32,
    h: f32,

    pub fn contains(self: Self, position: UiVec2) bool {
        return position.x >= self.x and position.x <= self.x + self.w and
            position.y >= self.y and position.y <= self.y + self.h;
    }
};

pub const UiState = struct {
    is_hovered: bool,
    is_clicked: bool,
    is_down: bool,
    is_right_clicked: bool,
    is_right_down: bool,
};

pub const UiStyle = struct {
    content_padding: f32 = 4.0,
    slot_padding: f32 = 8.0,
    text_padding: f32 = 4.0,
    item_padding: f32 = 4.0,
    title_padding: f32 = 4.0,
    title_margin_bottom: f32 = 4.0,
    text_color: UiVec4 = .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 },
    text_color_disabled: UiVec4 = .{ .r = 0.5, .g = 0.5, .b = 0.5, .a = 1.0 },

    action_button_width: f32 = 95.0,
    action_button_height: f32 = 40.0,
    action_button_spacing: f32 = 10.0,
};

pub const UiRenderer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    gctx: *zgpu.GraphicsContext,
    pipeline_layout: zgpu.PipelineLayoutHandle,
    pipeline: zgpu.RenderPipelineHandle,
    buffer: zgpu.BufferHandle,
    vertices: std.ArrayList(UiVertex),
    buffer_offset: u64 = 0,

    mouse: MouseState,
    style: UiStyle,
    interaction_enabled: bool = true,

    pub fn init(
        allocator: std.mem.Allocator,
        gctx: *zgpu.GraphicsContext,
        window: *zglfw.Window,
        global: *GlobalRenderState,
        style: UiStyle,
    ) !Self {
        const buffer = gctx.createBuffer(.{
            .usage = .{ .copy_dst = true, .vertex = true },
            .size = 1024 * 1024,
        });

        const pipeline_layout = gctx.createPipelineLayout(&.{
            global.layout,
        });

        const pipeline = try createPipeline(
            gctx,
            pipeline_layout,
        );

        const vertices = std.ArrayList(UiVertex).init(allocator);

        return .{
            .allocator = allocator,
            .gctx = gctx,
            .pipeline_layout = pipeline_layout,
            .pipeline = pipeline,
            .buffer = buffer,
            .vertices = vertices,
            .mouse = MouseState.init(window),
            .style = style,
        };
    }

    pub fn deinit(self: *Self) void {
        self.vertices.deinit();
    }

    pub fn beginFrame(
        self: *Self,
    ) void {
        self.vertices.clearRetainingCapacity();
        self.buffer_offset = 0;
        self.mouse.update();
        self.interaction_enabled = true;
    }

    pub fn setInteractionEnabled(self: *Self, enabled: bool) void {
        self.interaction_enabled = enabled;
    }

    fn pushQuad(self: *Self, rect: UiRect, color: UiVec4, data: u32, mode: u32) !void {
        const x = rect.x;
        const y = rect.y;
        const w = rect.w;
        const h = rect.h;

        try self.vertices.append(.{ .position = .{ .x = x, .y = y }, .uv = .{ .x = 0, .y = 0 }, .color = color, .data = data, .mode = mode });
        try self.vertices.append(.{ .position = .{ .x = x + w, .y = y }, .uv = .{ .x = 1, .y = 0 }, .color = color, .data = data, .mode = mode });
        try self.vertices.append(.{ .position = .{ .x = x + w, .y = y + h }, .uv = .{ .x = 1, .y = 1 }, .color = color, .data = data, .mode = mode });
        try self.vertices.append(.{ .position = .{ .x = x, .y = y }, .uv = .{ .x = 0, .y = 0 }, .color = color, .data = data, .mode = mode });
        try self.vertices.append(.{ .position = .{ .x = x + w, .y = y + h }, .uv = .{ .x = 1, .y = 1 }, .color = color, .data = data, .mode = mode });
        try self.vertices.append(.{ .position = .{ .x = x, .y = y + h }, .uv = .{ .x = 0, .y = 1 }, .color = color, .data = data, .mode = mode });
    }

    fn pushTextQuad(self: *Self, rect: UiRect, uv_rect: [4]f32, color: UiVec4) !void {
        const x = rect.x;
        const y = rect.y;
        const w = rect.w;
        const h = rect.h;

        const u = uv_rect[0];
        const v = uv_rect[1];
        const du = uv_rect[2];
        const dv = uv_rect[3];

        const mode = 2;
        const data = 0;

        try self.vertices.append(.{ .position = .{ .x = x, .y = y }, .uv = .{ .x = u, .y = v }, .color = color, .data = data, .mode = mode });
        try self.vertices.append(.{ .position = .{ .x = x + w, .y = y }, .uv = .{ .x = u + du, .y = v }, .color = color, .data = data, .mode = mode });
        try self.vertices.append(.{ .position = .{ .x = x + w, .y = y + h }, .uv = .{ .x = u + du, .y = v + dv }, .color = color, .data = data, .mode = mode });
        try self.vertices.append(.{ .position = .{ .x = x, .y = y }, .uv = .{ .x = u, .y = v }, .color = color, .data = data, .mode = mode });
        try self.vertices.append(.{ .position = .{ .x = x + w, .y = y + h }, .uv = .{ .x = u + du, .y = v + dv }, .color = color, .data = data, .mode = mode });
        try self.vertices.append(.{ .position = .{ .x = x, .y = y + h }, .uv = .{ .x = u, .y = v + dv }, .color = color, .data = data, .mode = mode });
    }

    pub fn rectangle(self: *Self, rect: UiRect, color: UiVec4) !void {
        try self.pushQuad(rect, color, 0, 0);
    }

    pub fn panel(self: *Self, rect: UiRect, title: ?[]const u8, font: ?*const Font) !UiRect {
        try self.pushQuad(rect, .{ .r = 0.1, .g = 0.1, .b = 0.1, .a = 0.9 }, 0, 0);

        var content_rect = UiRect{
            .x = rect.x + self.style.content_padding,
            .y = rect.y + self.style.content_padding,
            .w = rect.w - self.style.content_padding * 2,
            .h = rect.h - self.style.content_padding * 2,
        };

        if (title) |t| {
            if (font) |f| {
                const title_x = rect.x + self.style.title_padding;
                const title_y = rect.y + self.style.title_padding;

                try self.label(.{ .x = title_x, .y = title_y + f.ascent }, t, f, self.style.text_color);

                const header_height = self.style.title_padding + f.line_height + self.style.title_margin_bottom;

                content_rect.y = rect.y + header_height;
                content_rect.h = rect.h - header_height - self.style.content_padding;
            }
        }

        return content_rect;
    }

    pub fn sprite(self: *Self, rect: UiRect, s: Sprite) !void {
        const data = packSpriteForGpu(s);

        try self.pushQuad(rect, .{ .r = 1.0, .g = 1.0, .b = 1.0, .a = 1.0 }, data, 1);
    }

    pub fn inventorySlot(
        self: *Self,
        rect: UiRect,
        item: Item,
        amount: u32,
        is_selected: bool,
        font: *const Font,
    ) !UiState {
        const is_hovered = self.interaction_enabled and rect.contains(UiVec2{ .x = self.mouse.x, .y = self.mouse.y });

        var color = if (is_selected)
            UiVec4{ .r = 0.3, .g = 0.3, .b = 0.4, .a = 1.0 }
        else
            UiVec4{ .r = 0.15, .g = 0.15, .b = 0.15, .a = 1.0 };

        color = if (is_hovered)
            UiVec4{ .r = 0.4, .g = 0.4, .b = 0.5, .a = 1.0 }
        else
            color;

        try self.pushQuad(rect, color, 0, 0);

        switch (item) {
            .none => {},
            .resource => |r| {
                const s = Assets.getResourceSprite(r);
                const inset = self.style.slot_padding;
                const sprite_rect = UiRect{
                    .x = rect.x + inset,
                    .y = rect.y + inset,
                    .w = rect.w - inset * 2.0,
                    .h = rect.h - inset * 2.0,
                };
                try self.sprite(sprite_rect, s);
            },
            .component => |c| {
                const s = Assets.getComponentSprite(c);
                const inset = self.style.slot_padding;
                const sprite_rect = UiRect{
                    .x = rect.x + inset,
                    .y = rect.y + inset,
                    .w = rect.w - inset * 2.0,
                    .h = rect.h - inset * 2.0,
                };
                try self.sprite(sprite_rect, s);
            },
            else => return UiState{
                .is_hovered = is_hovered,
                .is_clicked = is_hovered and self.mouse.is_left_clicked,
                .is_down = is_hovered and self.mouse.is_left_down,
                .is_right_clicked = is_hovered and self.mouse.is_right_clicked,
                .is_right_down = is_hovered and self.mouse.is_right_down,
            },
        }

        if (amount > 0) {
            var buf: [16]u8 = undefined;
            const text = std.fmt.bufPrint(&buf, "{d}", .{amount}) catch "!";

            var text_w: f32 = 0;
            for (text) |char| {
                if (font.glyphs.get(char)) |glyph| {
                    text_w += glyph.dwidth;
                }
            }

            const tx = rect.x + rect.w - text_w - self.style.text_padding;
            const ty = rect.y + rect.h - self.style.text_padding;
            try self.label(.{ .x = tx, .y = ty }, text, font, self.style.text_color);
        }

        return UiState{
            .is_hovered = is_hovered,
            .is_clicked = is_hovered and self.mouse.is_left_clicked,
            .is_down = is_hovered and self.mouse.is_left_down,
            .is_right_clicked = is_hovered and self.mouse.is_right_clicked,
            .is_right_down = is_hovered and self.mouse.is_right_down,
        };
    }

    pub fn toolSlot(self: *Self, rect: UiRect, item: Item) !UiState {
        const is_hovered = self.interaction_enabled and rect.contains(UiVec2{ .x = self.mouse.x, .y = self.mouse.y });

        var color = UiVec4{ .r = 0.15, .g = 0.15, .b = 0.15, .a = 1.0 };

        color = if (is_hovered)
            UiVec4{ .r = 0.4, .g = 0.4, .b = 0.5, .a = 1.0 }
        else
            color;

        try self.pushQuad(rect, color, 0, 0);

        switch (item) {
            .none => {},
            .resource => {},
            .tool => |t| {
                const s = Assets.getToolSprite(t);
                const inset = self.style.slot_padding;
                const sprite_rect = UiRect{
                    .x = rect.x + inset,
                    .y = rect.y + inset,
                    .w = rect.w - inset * 2.0,
                    .h = rect.h - inset * 2.0,
                };
                try self.sprite(sprite_rect, s);
            },
            .recipe => {},
            .component => {},
        }

        return UiState{
            .is_hovered = is_hovered,
            .is_clicked = is_hovered and self.mouse.is_left_clicked,
            .is_down = is_hovered and self.mouse.is_left_down,
            .is_right_clicked = is_hovered and self.mouse.is_right_clicked,
            .is_right_down = is_hovered and self.mouse.is_right_down,
        };
    }

    pub fn recipeSlot(self: *Self, rect: UiRect, item: Item, is_selected: bool) !UiState {
        const is_hovered = self.interaction_enabled and rect.contains(UiVec2{ .x = self.mouse.x, .y = self.mouse.y });

        var color = if (is_selected)
            UiVec4{ .r = 0.3, .g = 0.3, .b = 0.4, .a = 1.0 }
        else
            UiVec4{ .r = 0.15, .g = 0.15, .b = 0.15, .a = 1.0 };

        color = if (is_hovered)
            UiVec4{ .r = 0.4, .g = 0.4, .b = 0.5, .a = 1.0 }
        else
            color;

        try self.pushQuad(rect, color, 0, 0);

        switch (item) {
            .none => {},
            .resource => {},
            .tool => {},
            .recipe => |r| {
                const s = Assets.getRecipeSprite(r);
                const inset = self.style.slot_padding;
                const sprite_rect = UiRect{
                    .x = rect.x + inset,
                    .y = rect.y + inset,
                    .w = rect.w - inset * 2.0,
                    .h = rect.h - inset * 2.0,
                };
                try self.sprite(sprite_rect, s);
            },
            .component => {},
        }

        return UiState{
            .is_hovered = is_hovered,
            .is_clicked = is_hovered and self.mouse.is_left_clicked,
            .is_down = is_hovered and self.mouse.is_left_down,
            .is_right_clicked = is_hovered and self.mouse.is_right_clicked,
            .is_right_down = is_hovered and self.mouse.is_right_down,
        };
    }

    pub fn button(
        self: *Self,
        rect: UiRect,
        is_active: bool,
        is_disabled: bool,
        text: []const u8,
        font: *const Font,
    ) !UiState {
        const is_hovered = self.interaction_enabled and rect.contains(UiVec2{ .x = self.mouse.x, .y = self.mouse.y });
        var color = if (is_active)
            UiVec4{ .r = 0.25, .g = 0.25, .b = 0.35, .a = 1.0 }
        else
            UiVec4{ .r = 0.18, .g = 0.18, .b = 0.22, .a = 1.0 };

        color = if (is_disabled)
            UiVec4{ .r = 0.10, .g = 0.10, .b = 0.18, .a = 1.0 }
        else if (is_hovered)
            UiVec4{ .r = 0.35, .g = 0.35, .b = 0.45, .a = 1.0 }
        else
            color;

        try self.pushQuad(rect, color, 0, 0);

        var text_w: f32 = 0;
        for (text) |char| {
            if (font.glyphs.get(char)) |glyph| {
                text_w += glyph.dwidth;
            }
        }

        const text_x = rect.x + (rect.w - text_w) / 2.0;
        const text_y = rect.y + (rect.h + font.ascent) / 2.0;

        try self.label(
            UiVec2{ .x = text_x, .y = text_y },
            text,
            font,
            if (is_disabled) self.style.text_color_disabled else self.style.text_color,
        );

        return UiState{
            .is_hovered = !is_disabled and is_hovered,
            .is_clicked = !is_disabled and is_hovered and self.mouse.is_left_clicked,
            .is_down = !is_disabled and is_hovered and self.mouse.is_left_down,
            .is_right_clicked = !is_disabled and is_hovered and self.mouse.is_right_clicked,
            .is_right_down = !is_disabled and is_hovered and self.mouse.is_right_down,
        };
    }

    pub fn label(self: *Self, pos: UiVec2, text: []const u8, font: *const Font, color: UiVec4) !void {
        const start_x = pos.x;
        var x = start_x;
        var y = pos.y;

        for (text) |char| {
            if (char == '\n') {
                y += font.line_height;
                x = start_x;
            }

            if (font.glyphs.get(char)) |glyph| {
                const qx = x + glyph.offset_x;
                const qy = y - glyph.offset_y - glyph.height;
                const qw = glyph.width;
                const qh = glyph.height;

                try self.pushTextQuad(
                    .{ .x = qx, .y = qy, .w = qw, .h = qh },
                    glyph.uv_rect,
                    color,
                );

                x += glyph.dwidth;
            }
        }
    }

    pub fn tooltip(self: *Self, x: f32, y: f32, text: []const u8, font: *const Font) !void {
        var line_breaks: f32 = 0;
        for (text) |char| {
            if (char == '\n') {
                line_breaks += 1;
            }
        }

        var max: f32 = 0;
        var current_w: f32 = 0;
        for (text) |char| {
            if (char == '\n') {
                if (current_w > max) {
                    max = current_w;
                }

                current_w = 0;
                continue;
            }

            if (font.glyphs.get(char)) |glyph| {
                current_w += glyph.dwidth;
            }
        }

        if (current_w > max) {
            max = current_w;
        }

        const padding = self.style.content_padding;
        const w = max;
        const h = font.line_height * (line_breaks + 1);

        const rect = UiRect{ .x = x, .y = y, .w = w + padding * 2, .h = h + padding * 2 };
        _ = try self.panel(rect, null, null);

        try self.label(.{ .x = x + padding, .y = y + padding + font.ascent }, text, font, self.style.text_color);
    }

    pub const DropdownResult = struct {
        rect: UiRect,
        selected_index: ?usize,
    };

    pub const DropdownItem = struct {
        text: []const u8,
        is_enabled: bool,
    };

    pub fn dropdown(self: *Self, x: f32, y: f32, items: []const DropdownItem, font: *const Font) !DropdownResult {
        var max_w: f32 = 0;
        for (items) |item| {
            var tw: f32 = 0;
            for (item.text) |char| {
                if (font.glyphs.get(char)) |glyph| tw += glyph.dwidth;
            }
            if (tw > max_w) max_w = tw;
        }

        const padding = self.style.content_padding;
        const item_padding = self.style.item_padding;
        const item_height = font.line_height + item_padding * 2.0;

        const w = max_w + (padding + item_padding) * 2.0;
        const h = @as(f32, @floatFromInt(items.len)) * item_height + padding * 2.0;

        const rect = UiRect{ .x = x, .y = y, .w = w, .h = h };

        // background
        _ = try self.panel(rect, null, null);

        var selected_index: ?usize = null;

        for (items, 0..) |item, i| {
            const item_rect = UiRect{
                .x = x + padding,
                .y = y + padding + (@as(f32, @floatFromInt(i)) * item_height),
                .w = w - padding * 2.0,
                .h = item_height,
            };

            const is_hovered = item.is_enabled and self.interaction_enabled and item_rect.contains(UiVec2{ .x = self.mouse.x, .y = self.mouse.y });

            if (is_hovered) {
                try self.pushQuad(
                    item_rect,
                    .{ .r = 0.3, .g = 0.3, .b = 0.4, .a = 1.0 },
                    0,
                    0,
                );

                if (self.mouse.is_left_clicked) {
                    selected_index = i;
                }
            }

            try self.label(.{
                .x = item_rect.x + item_padding,
                .y = item_rect.y + item_padding + font.ascent,
            }, item.text, font, if (item.is_enabled) self.style.text_color else self.style.text_color_disabled);
        }

        return DropdownResult{
            .rect = rect,
            .selected_index = selected_index,
        };
    }

    pub fn flush(
        self: *Self,
        pass: zgpu.wgpu.RenderPassEncoder,
        global: *const GlobalRenderState,
    ) void {
        if (self.vertices.items.len == 0) {
            return;
        }

        const slice = std.mem.sliceAsBytes(self.vertices.items);
        self.gctx.queue.writeBuffer(
            self.gctx.lookupResource(self.buffer).?,
            self.buffer_offset,
            u8,
            slice,
        );

        const pipeline = self.gctx.lookupResource(self.pipeline).?;
        const global_bind_group = self.gctx.lookupResource(global.bind_group).?;
        const buffer = self.gctx.lookupResource(self.buffer).?;

        const count: u32 = @intCast(self.vertices.items.len);

        pass.setPipeline(pipeline);
        pass.setBindGroup(0, global_bind_group, null);
        pass.setVertexBuffer(0, buffer, self.buffer_offset, @sizeOf(UiVertex) * count);
        pass.draw(count, 1, 0, 0);

        self.buffer_offset += @sizeOf(UiVertex) * count;
        self.vertices.clearRetainingCapacity();
    }
};

fn createPipeline(
    gctx: *zgpu.GraphicsContext,
    pipeline_layout: zgpu.PipelineLayoutHandle,
) !zgpu.RenderPipelineHandle {
    const vs_module = shader_utils.createShaderModuleWithCommon(
        gctx.device,
        @embedFile("../shaders/ui_vertex.wgsl"),
        "main",
    );
    defer vs_module.release();

    const fs_module = shader_utils.createShaderModuleWithCommon(
        gctx.device,
        @embedFile("../shaders/ui_fragment.wgsl"),
        "main",
    );
    defer fs_module.release();

    const color_targets = [_]wgpu.ColorTargetState{
        .{
            .format = gctx.swapchain_descriptor.format,
            .blend = &wgpu.BlendState{
                .color = .{
                    .src_factor = .src_alpha,
                    .dst_factor = .one_minus_src_alpha,
                    .operation = .add,
                },
                .alpha = .{
                    .src_factor = .one,
                    .dst_factor = .one_minus_src_alpha,
                    .operation = .add,
                },
            },
            .write_mask = .all,
        },
    };

    const vertex_attrs = [_]wgpu.VertexAttribute{
        .{
            .format = .float32x2,
            .offset = @offsetOf(UiVertex, "position"),
            .shader_location = 0,
        },

        .{
            .format = .float32x2,
            .offset = @offsetOf(UiVertex, "uv"),
            .shader_location = 1,
        },
        .{
            .format = .float32x4,
            .offset = @offsetOf(UiVertex, "color"),
            .shader_location = 2,
        },
        .{
            .format = .uint32,
            .offset = @offsetOf(UiVertex, "data"),
            .shader_location = 3,
        },
        .{
            .format = .uint32,
            .offset = @offsetOf(UiVertex, "mode"),
            .shader_location = 4,
        },
    };

    const vertex_buffers = [_]wgpu.VertexBufferLayout{
        .{
            .array_stride = @sizeOf(UiVertex),
            .step_mode = .vertex,
            .attribute_count = vertex_attrs.len,
            .attributes = &vertex_attrs,
        },
    };

    const pipeline_descriptor = wgpu.RenderPipelineDescriptor{
        .vertex = .{
            .module = vs_module,
            .entry_point = "main",
            .buffer_count = vertex_buffers.len,
            .buffers = &vertex_buffers,
        },
        .primitive = .{
            .topology = .triangle_list,
            .front_face = .ccw,
            .cull_mode = .none,
        },
        .fragment = &wgpu.FragmentState{
            .module = fs_module,
            .entry_point = "main",
            .target_count = color_targets.len,
            .targets = &color_targets,
        },
    };

    return gctx.createRenderPipeline(pipeline_layout, pipeline_descriptor);
}
