const CHUNK_W = 64;
const CHUNK_H = 64;

struct GlobalUniforms {
  screen_wh: vec4<f32>,
  dt: f32,
  t: f32,
  tile_size: f32,
  _pad0: f32,
};

struct ChunkUniforms {
  chunk_xy: vec4<f32>,
  chunk_wh: vec4<f32>,
};

struct Tile {
  category: u32,
  sheet: u32,
  sprite: u32,
};

@group(0) @binding(0) var<uniform> global_u: GlobalUniforms;
@group(0) @binding(2) var u_atlas: texture_2d_array<f32>;
@group(0) @binding(3) var u_sampler: sampler;

@group(1) @binding(0) var<uniform> chunk_u: ChunkUniforms;
@group(1) @binding(1) var u_tilemap: texture_2d<u32>;

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

fn get_sprite_uv(tile: Tile, tile_pos: vec2<f32>) -> vec2<f32> {
  let sprites_per_row = 32u;
  let sprite_size = 1.0 / 32.0;
  
  let sprite_x = tile.sprite % sprites_per_row;
  let sprite_y = tile.sprite / sprites_per_row;
  
  let tile_uv = fract(tile_pos);
  let uv = vec2<f32>(
      (f32(sprite_x) + tile_uv.x) * sprite_size,
      (f32(sprite_y) + tile_uv.y) * sprite_size
  );

  return uv;
}

struct FSIn {
  @location(0) tile_pos: vec2<f32>,
};

@fragment
fn main(in: FSIn) -> @location(0) vec4<f32> {
  let tile = fetch_tile(in.tile_pos);

  if (tile.category == 0u) {
      return vec4<f32>(0.0, 0.0, 0.0, 1.0);
  }

  let uv = get_sprite_uv(tile, in.tile_pos);
  let color = textureSampleLevel(u_atlas, u_sampler, uv, tile.sheet, 0.0);
  
  return color;
}
