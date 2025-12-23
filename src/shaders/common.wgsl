struct GlobalUniforms {
  dt: f32,
  t: f32,
  mode: u32,
  _pad0: f32,
  screen_wh: vec4<f32>,
  camera_xy: vec4<f32>,
  camera_zoom: f32,
  _pad_removed_tile_size: f32,
  _pad1: f32,
  _pad2: f32,
  hover_xy: vec4<f32>,
};

struct ChunkUniforms {
  chunk_xy: vec4<f32>,
  chunk_wh: vec4<f32>,
};

struct Tile {
  category: u32,
  sheet: u32,
  sprite: u32,
  has_overlay: u32,
  overlay_sheet: u32,
  overlay_sprite: u32,
};

const CHUNK_W = 64;
const CHUNK_H = 64;
const MAX_TILE_WIDTH = 16;
const MAX_TILE_HEIGHT = 16;

@group(0) @binding(0)
var<uniform> globals: GlobalUniforms;

fn unpack_tile(id: u32) -> Tile {
  let sprite: u32 = id & 0x3FFu;
  let category: u32 = (id >> 10u) & 0x07u;
  let sheet: u32 = (id >> 13u) & 0x0Fu;
  
  let overlay_sprite: u32 = (id >> 17u) & 0x3FFu;
  let overlay_sheet: u32 = (id >> 27u) & 0x0Fu;
  let has_overlay: u32 = (id >> 31u) & 0x01u;

  return Tile(category, sheet, sprite, has_overlay, overlay_sheet, overlay_sprite);
}

fn get_sprite_uv(tile: Tile, tile_uv: vec2<f32>) -> vec2<f32> {
  let sprites_per_row = 32u;
  let sprite_size = 1.0 / 32.0;
  
  let sprite_x = tile.sprite % sprites_per_row;
  let sprite_y = tile.sprite / sprites_per_row;
  
  let uv = vec2<f32>(
      (f32(sprite_x) + tile_uv.x) * sprite_size,
      (f32(sprite_y) + tile_uv.y) * sprite_size
  );
  
  return uv;
}

fn world_to_ndc(world_pos: vec2<f32>) -> vec2<f32> {
  let camera_pos = globals.camera_xy.xy;
  let view_pos = world_pos - camera_pos;
  let view_px = view_pos * globals.camera_zoom;
  let half_screen = globals.screen_wh.xy * 0.5;
  
  return vec2<f32>(
      view_px.x / half_screen.x,
      -view_px.y / half_screen.y
  );
}

fn screen_to_ndc(screen_pos: vec2<f32>) -> vec2<f32> {
  let screen = globals.screen_wh.xy;
  let px = (screen_pos.x / screen.x) * 2.0 - 1.0;
  let py = 1.0 - (screen_pos.y / screen.y) * 2.0;
  
  return vec2<f32>(
      px,
      py,
  );
}
