struct GlobalUniforms {
    dt: f32,
    t: f32,
    _pad0: f32,
    _pad1: f32,
    screen_wh: vec4<f32>,
    camera_xy: vec4<f32>,
    tile_size: f32,
};

@group(0) @binding(0) var<uniform> globals: GlobalUniforms;
@group(0) @binding(2) var u_atlas: texture_2d_array<f32>;
@group(0) @binding(3) var u_sampler: sampler;

struct FSIn {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@fragment
fn main(in: FSIn) -> @location(0) vec4<f32> {
    let sprite_index = 0u;
    let color = textureSample(u_atlas, u_sampler, in.uv, sprite_index);

    // let color = vec4<f32>(1.0);
    return color;
}
