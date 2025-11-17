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

struct ChunkUniforms {
    chunk_xy: vec4<f32>,
    chunk_wh: vec4<f32>,
};

@group(0) @binding(0)
var<uniform> globals: GlobalUniforms;

@group(1) @binding(0)
var<uniform> chunk_u: ChunkUniforms;

struct VSOut {
    @builtin(position) pos: vec4<f32>,
    @location(0) local_tile: vec2<f32>,
};

@vertex
fn main(@builtin(vertex_index) vi: u32) -> VSOut {
    var out: VSOut;

    let chunk_w = chunk_u.chunk_wh.x;
    let chunk_h = chunk_u.chunk_wh.y;

    let quad: array<vec2<f32>, 6> = array<vec2<f32>, 6>(
        vec2<f32>(0.0,      0.0),
        vec2<f32>(chunk_w,  0.0),
        vec2<f32>(0.0,      chunk_h),

        vec2<f32>(0.0,      chunk_h),
        vec2<f32>(chunk_w,  0.0),
        vec2<f32>(chunk_w,  chunk_h),
    );

    let local_tile = quad[vi];
    out.local_tile = local_tile;

    let chunk_origin_tiles = chunk_u.chunk_xy.xy * vec2<f32>(chunk_w, chunk_h);

    let world_tile = chunk_origin_tiles + local_tile;
    let camera_tile = globals.camera_xy.xy; 
    let view_tile = world_tile - camera_tile;

    let view_px = view_tile * globals.tile_size * globals.camera_zoom;

    let half_screen = globals.screen_wh.xy * 0.5;
    let ndc_x = view_px.x / half_screen.x;
    let ndc_y = -view_px.y / half_screen.y;

    out.pos = vec4<f32>(ndc_x, ndc_y, 0.0, 1.0);
    return out;
}
