struct VertexInput {
    @location(0) size: vec4<f32>,
    @location(1) position: vec4<f32>,
    @location(2) rotation: vec4<f32>,
};

struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex
fn main(
    @builtin(vertex_index) vertex_index: u32,
    input: VertexInput,
) -> VertexOutput {
    var output: VertexOutput;

    let quad: array<vec2<f32>, 6> = array<vec2<f32>, 6>(
        vec2<f32>(0.0, 0.0),
        vec2<f32>(1.0, 0.0),
        vec2<f32>(0.0, 1.0),
        
        vec2<f32>(0.0, 1.0),
        vec2<f32>(1.0, 0.0),
        vec2<f32>(1.0, 1.0),
    );

    let quad_pos = quad[vertex_index];
    output.uv = quad_pos;

    let angle = input.rotation.x;
    let rotation_matrix: mat2x2<f32> = mat2x2<f32>(
        cos(angle), sin(angle),
        -sin(angle), cos(angle)
    );

    let rotated_pos = rotation_matrix * (quad_pos - vec2<f32>(0.5, 0.5));
    
    // let sprite_size = input.size.xy;
    let sprite_size = vec2<f32>(8.0);
    let sprite_position = input.position.xy;
    
    let world_pos = sprite_position + rotated_pos * sprite_size;
    let ndc_pos = world_to_ndc(world_pos);
    output.position = vec4<f32>(ndc_pos, 0.0, 1.0);
    return output;
}
