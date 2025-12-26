struct FragmentInput {
  @builtin(position) position: vec4<f32>,
  @location(1) uv: vec2<f32>,
  @location(2) color: vec4<f32>,
  @location(3) @interpolate(flat) data: u32,
  @location(4) @interpolate(flat) mode: u32,
};

@group(0) @binding(2) var atlas_texture: texture_2d_array<f32>;
@group(0) @binding(3) var atlas_sampler: sampler;

@fragment
fn main(
  input: FragmentInput
) -> @location(0) vec4<f32> {
  if (input.mode == 1u) {
    let tile = unpack_tile(input.data);
    let uv = get_sprite_uv(tile, input.uv);
    let tex_color = textureSampleLevel(atlas_texture, atlas_sampler, uv, tile.sheet, 0.0);

    return tex_color * input.color;
  } else if (input.mode == 2u) {
    let sheet = 0u;
    let tex_color = textureSampleLevel(atlas_texture, atlas_sampler, input.uv, sheet, 0.0);

    return tex_color * input.color;
  }

  return input.color;
}
