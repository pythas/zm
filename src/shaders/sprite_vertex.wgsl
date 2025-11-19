struct GlobalUniforms {
    dt: f32,
    t: f32,
    _pad0: f32,
    _pad1: f32,
    screen_wh: vec4<f32>,
    camera_xy: vec4<f32>,
    camera_zoom: f32,
    tile_size: f32,
};

@group(0) @binding(0)
var<uniform> globals: GlobalUniforms;

struct VSIn {
    @location(0) wh: vec4<f32>,
    @location(1) position: vec4<f32>,
    @location(2) rotation: vec4<f32>,
};

struct VSOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex
fn main(
  @builtin(vertex_index) vi: u32,
  in: VSIn,
) -> VSOut {
    var out: VSOut;

    let quad: array<vec2<f32>, 6> = array<vec2<f32>, 6>(
        vec2<f32>(0.0, 0.0),
        vec2<f32>(1.0, 0.0),
        vec2<f32>(0.0, 1.0),

        vec2<f32>(0.0, 1.0),
        vec2<f32>(1.0, 0.0),
        vec2<f32>(1.0, 1.0),
    );

    let pos = quad[vi];
    out.uv = pos;

    let angle = in.rotation.x;

    let rot: mat2x2<f32> = mat2x2<f32>(
        cos(angle), sin(angle),
        -sin(angle),  cos(angle)
    );

    let rotated = rot * (pos - vec2<f32>(0.5, 0.5));

    // let sprite_size = in.wh.xy;
    let sprite_size = vec2<f32>(8.0);
    let sprite_pos = in.position.xy;
    
    let world_pos = sprite_pos + rotated * sprite_size;
    let camera_pos = globals.camera_xy.xy; 
    let view_pos = world_pos - camera_pos;

    let view_px = view_pos * globals.tile_size * globals.camera_zoom;

    let half_screen = globals.screen_wh.xy * 0.5;
    let ndc_x = view_px.x / half_screen.x;
    let ndc_y = -view_px.y / half_screen.y;

    out.pos = vec4<f32>(ndc_x, ndc_y, 0.0, 1.0);
    return out;
}
