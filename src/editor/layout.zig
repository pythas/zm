const UiRect = @import("../renderer/ui_renderer.zig").UiRect;
const tilemapWidth = @import("../tile.zig").tilemapWidth;
const tilemapHeight = @import("../tile.zig").tilemapHeight;

pub const EditorLayout = struct {
    const scaling: f32 = 3.0;
    const padding: f32 = 10.0;
    const tile_size_base: f32 = 8.0;
    const header_height: f32 = 50.0;

    scale: f32,
    tile_size: f32,

    ship_panel_rect: UiRect,
    grid_rect: UiRect,
    inventory_rect: UiRect,
    tools_rect: UiRect,
    recipe_rect: UiRect,
    crafting_rect: UiRect,

    pub fn compute(screen_w: f32, screen_h: f32) EditorLayout {
        _ = screen_w;
        _ = screen_h;

        const tile_size = tile_size_base * scaling;

        const ship_w = (tile_size_base * tilemapWidth * scaling) + (padding * 2);
        const ship_h = (tile_size_base * tilemapWidth * scaling) + (padding * 2);
        const ship_y = padding;
        const ship_rect = UiRect{
            .x = padding,
            .y = ship_y,
            .w = ship_w,
            .h = ship_h,
        };

        const grid_w = tile_size * tilemapWidth;
        const grid_h = tile_size * tilemapHeight;
        const grid_rect = UiRect{
            .x = ship_rect.x + padding,
            .y = ship_rect.y + padding,
            .w = grid_w,
            .h = grid_h,
        };

        const inv_w = tile_size_base * scaling * 8;
        const inv_h = tile_size_base * scaling * 8;
        const inv_rect = UiRect{
            .x = ship_rect.x + ship_rect.w + padding,
            .y = padding,
            .w = inv_w,
            .h = inv_h,
        };

        const tools_w = tile_size_base * scaling * 8;
        const tools_h = tile_size_base * scaling * 4;
        const tools_rect = UiRect{
            .x = inv_rect.x + inv_rect.w + padding,
            .y = padding,
            .w = tools_w,
            .h = tools_h,
        };

        const recipe_w = tile_size_base * scaling * 8;
        const recipe_h = tile_size_base * scaling * 4;
        const recipe_rect = UiRect{
            .x = ship_rect.x + ship_rect.w + padding,
            .y = inv_rect.y + inv_rect.h + padding,
            .w = recipe_w,
            .h = recipe_h,
        };

        const crafting_w = tile_size_base * scaling * 8;
        const crafting_h = tile_size_base * scaling * 1;
        const crafting_rect = UiRect{
            .x = recipe_rect.x,
            .y = recipe_rect.y + recipe_rect.h + padding,
            .w = crafting_w,
            .h = crafting_h,
        };

        return .{
            .scale = scaling,
            .tile_size = tile_size,
            .ship_panel_rect = ship_rect,
            .grid_rect = grid_rect,
            .inventory_rect = inv_rect,
            .tools_rect = tools_rect,
            .recipe_rect = recipe_rect,
            .crafting_rect = crafting_rect,
        };
    }

    pub fn getHoveredTile(self: EditorLayout, mouse_x: f32, mouse_y: f32) ?struct { x: i32, y: i32 } {
        if (mouse_x >= self.grid_rect.x and mouse_x < self.grid_rect.x + self.grid_rect.w and
            mouse_y >= self.grid_rect.y and mouse_y < self.grid_rect.y + self.grid_rect.h)
        {
            const local_x = mouse_x - self.grid_rect.x;
            const local_y = mouse_y - self.grid_rect.y;
            return .{
                .x = @intFromFloat(local_x / self.tile_size),
                .y = @intFromFloat(local_y / self.tile_size),
            };
        }
        return null;
    }
};
