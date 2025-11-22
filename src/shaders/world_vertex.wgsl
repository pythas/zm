@group(1) @binding(0)
var<uniform> chunk_uniforms: ChunkUniforms;

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) local_tile_pos: vec2<f32>,
};

@vertex
fn main(@builtin(vertex_index) vertex_index: u32) -> VertexOutput {
    var output: VertexOutput;

    let chunk_w = chunk_uniforms.chunk_wh.x;
    let chunk_h = chunk_uniforms.chunk_wh.y;

    let quad: array<vec2<f32>, 6> = array<vec2<f32>, 6>(
        vec2<f32>(0.0,      0.0),
        vec2<f32>(chunk_w,  0.0),
        vec2<f32>(0.0,      chunk_h),
        
        vec2<f32>(0.0,      chunk_h),
        vec2<f32>(chunk_w,  0.0),
        vec2<f32>(chunk_w,  chunk_h),
    );

    let local_tile_pos = quad[vertex_index];
    output.local_tile_pos = local_tile_pos;

    let chunk_xy = chunk_uniforms.chunk_xy.xy;
    let chunk_size = vec2<f32>(chunk_w, chunk_h);
    let chunk_origin_tiles = chunk_xy * chunk_size - chunk_size / 2;
    let world_tile_pos = chunk_origin_tiles + local_tile_pos;
    
    let ndc_pos = world_to_ndc(world_tile_pos);
    output.position = vec4<f32>(ndc_pos, 0.0, 1.0);
    
    return output;
}
