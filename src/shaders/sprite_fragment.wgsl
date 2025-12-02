@group(0) @binding(2) var atlas_texture: texture_2d_array<f32>;
@group(0) @binding(3) var atlas_sampler: sampler;

@group(1) @binding(0) var tilemap_texture: texture_2d<u32>;

fn fetch_tile(tile_pos: vec2<f32>) -> Tile {
  let tx = clamp(i32(floor(tile_pos.x)), 0, CHUNK_W - 1);
  let ty = clamp(i32(floor(tile_pos.y)), 0, CHUNK_H - 1);

  let id = textureLoad(tilemap_texture, vec2<i32>(tx, ty), 0).r;
  return unpack_tile(id);
}

struct FragmentInput {
  @builtin(position) position: vec4<f32>,
  @location(0) uv: vec2<f32>,
};

fn grid(tile_uv: vec2<f32>) -> vec4<f32> {
  let edge = min(
      min(tile_uv.x, 1.0 - tile_uv.x),
      min(tile_uv.y, 1.0 - tile_uv.y),
  );
  let grid_thickness = 0.06;
  let grid_mask = step(edge, grid_thickness);
  let grid_color = vec4<f32>(0.3, 0.3, 0.3, 1.0);
  let base = vec4<f32>(0.0, 0.0, 0.0, 1.0);

  return mix(base, grid_color, grid_mask);
}

@fragment
fn main(input: FragmentInput) -> @location(0) vec4<f32> {
  let tile_x = clamp(i32(floor(input.uv.x * f32(MAX_TILE_WIDTH))), 0, MAX_TILE_WIDTH - 1);
  let tile_y = clamp(i32(floor(input.uv.y * f32(MAX_TILE_HEIGHT))), 0, MAX_TILE_HEIGHT - 1);

  let tile = fetch_tile(vec2<f32>(f32(tile_x), f32(tile_y)));

  let tile_uv = fract(input.uv * vec2<f32>(f32(MAX_TILE_WIDTH), f32(MAX_TILE_HEIGHT)));
  let uv = get_sprite_uv(tile, tile_uv);
  var color = textureSampleLevel(atlas_texture, atlas_sampler, uv, tile.sheet, 0.0);

  if (tile.category == 0u) {
      color = vec4<f32>(0.0);
  }

  if globals.mode == 1u {
    let grid_color = grid(tile_uv);
    var a = color.a;
    color = mix(grid_color, color, a);

    let hover_active = globals.hover_xy.z > 0.5;
    let hover_tx = i32(globals.hover_xy.x);
    let hover_ty = i32(globals.hover_xy.y);

    if (hover_active && tile_x == hover_tx && tile_y == hover_ty) {
      let highlight = vec4<f32>(1.0, 1.0, 1.0, 1.0);
      let edge = min(
          min(tile_uv.x, 1.0 - tile_uv.x),
          min(tile_uv.y, 1.0 - tile_uv.y),
      );
      let highlight_thickness = 0.06;
      let highlight_mask = step(edge, highlight_thickness);

      color = mix(color, highlight, highlight_mask);
    }
  }

  return color;
}
