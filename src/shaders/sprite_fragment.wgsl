@group(0) @binding(2) var atlas_texture: texture_2d_array<f32>;
@group(0) @binding(3) var atlas_sampler: sampler;

@group(1) @binding(0) var tilemap_texture: texture_2d<u32>;

fn fetch_tile(tile_pos: vec2<i32>, texture_size: vec2<i32>) -> Tile {
  let tx = clamp(tile_pos.x, 0, texture_size.x - 1);
  let ty = clamp(tile_pos.y, 0, texture_size.y - 1);

  let id = textureLoad(tilemap_texture, vec2<i32>(tx, ty), 0).r;
  return unpack_tile(id);
}

struct FragmentInput {
  @builtin(position) position: vec4<f32>,
  @location(0) uv: vec2<f32>,
  @location(1) size: vec2<f32>,
  @location(2) hover: vec4<f32>,
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
  let texture_dimensions = textureDimensions(tilemap_texture);
  let tile_count = vec2<f32>(f32(texture_dimensions.x), f32(texture_dimensions.y));
 
  let tile_x = clamp(i32(floor(input.uv.x * tile_count.x)), 0, i32(texture_dimensions.x) - 1);
  let tile_y = clamp(i32(floor(input.uv.y * tile_count.y)), 0, i32(texture_dimensions.y) - 1);

  let tile = fetch_tile(vec2<i32>(tile_x, tile_y), vec2<i32>(i32(texture_dimensions.x), i32(texture_dimensions.y)));

  let tile_uv = fract(input.uv * tile_count);
  let uv = get_sprite_uv(tile, tile_uv);
  var color = textureSampleLevel(atlas_texture, atlas_sampler, uv, tile.sheet, 0.0);

  if (tile.has_overlay != 0u) {
    let overlay_tile = Tile(0u, tile.overlay_sheet, tile.overlay_sprite, 0u, 0u, 0u);
    let overlay_uv = get_sprite_uv(overlay_tile, tile_uv);
    let overlay_color = textureSampleLevel(atlas_texture, atlas_sampler, overlay_uv, tile.overlay_sheet, 0.0);

    color = mix(color, overlay_color, overlay_color.a * color.a);
  }

  if (tile.category == 0u) {
      color = vec4<f32>(0.0);
  }

  if globals.mode == 0u {
    let hover_active = input.hover.z > 0.5;
    let hover_tx = i32(input.hover.x);
    let hover_ty = i32(input.hover.y);

    if (hover_active && tile_x == hover_tx && tile_y == hover_ty) {
      let grid_color = grid(tile_uv);
      var a = color.a;
      color = mix(grid_color, color, a);

      let highlight = vec4<f32>(1.0, 1.0, 1.0, 1.0);
      let edge = min(
          min(tile_uv.x, 1.0 - tile_uv.x),
          min(tile_uv.y, 1.0 - tile_uv.y),
      );
      let highlight_thickness = 0.06;
      let highlight_mask = step(edge, highlight_thickness);

      color = mix(color, highlight, highlight_mask);
    }
  } else if globals.mode == 1u {
    let grid_color = grid(tile_uv);
    var a = color.a;
    color = mix(grid_color, color, a);

    let hover_active = input.hover.z > 0.5;
    let hover_tx = i32(input.hover.x);
    let hover_ty = i32(input.hover.y);

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
