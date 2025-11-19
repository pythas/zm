const CHUNK_W = 64;
const CHUNK_H = 64;
const MAX_TILE_WIDTH = 8;
const MAX_TILE_HEIGHT = 8;

struct GlobalUniforms {
  dt: f32,
  t: f32,
  _pad0: f32,
  _pad1: f32,
  screen_wh: vec4<f32>,
  camera_xy: vec4<f32>,
  tile_size: f32,
};

struct Tile {
  category: u32,
  sheet: u32,
  sprite: u32,
};

@group(0) @binding(0) var<uniform> globals: GlobalUniforms;
@group(0) @binding(2) var u_atlas: texture_2d_array<f32>;
@group(0) @binding(3) var u_sampler: sampler;

@group(1) @binding(0) var u_tilemap: texture_2d<u32>;

fn fetch_tile(pos: vec2<f32>) -> Tile {
  let tx = clamp(i32(floor(pos.x)), 0, CHUNK_W - 1);
  let ty = clamp(i32(floor(pos.y)), 0, CHUNK_H - 1);

  let id = textureLoad(u_tilemap, vec2<i32>(tx, ty), 0).r;
  return unpack_tile(id);
}

fn unpack_tile(id: u32) -> Tile {
  let sprite: u32 = id & 0x3FFu;
  let category: u32 = (id >> 10u) & 0x0Fu;
  let sheet: u32 = (id >> 14u) & 0x0Fu;

  return Tile(category, sheet, sprite);
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

struct FSIn {
  @builtin(position) pos: vec4<f32>,
  @location(0) uv: vec2<f32>,
};

@fragment
fn main(in: FSIn) -> @location(0) vec4<f32> {
  let tile_x = clamp(i32(floor(in.uv.x * f32(MAX_TILE_WIDTH))), 0, MAX_TILE_WIDTH - 1);
  let tile_y = clamp(i32(floor(in.uv.y * f32(MAX_TILE_HEIGHT))), 0, MAX_TILE_HEIGHT - 1);

  let tile = fetch_tile(vec2<f32>(f32(tile_x), f32(tile_y)));

  let is_empty = tile.category == 0u;

  if is_empty {
    return vec4<f32>(0.0);
  }

  let tile_uv = fract(in.uv * vec2<f32>(f32(MAX_TILE_WIDTH), f32(MAX_TILE_HEIGHT)));

  let uv = get_sprite_uv(tile, tile_uv);
  let color = textureSampleLevel(u_atlas, u_sampler, uv, tile.sheet, 0.0);

  return color;
}
