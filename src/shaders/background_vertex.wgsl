struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex
fn main(@builtin(vertex_index) vertex_index: u32) -> VertexOutput {
    // Big triangle trick
    // 0: (-1, -1) -> uv (0, 1) ? No, depends on mapping
    // We want full screen coverage in NDC (-1 to 1)
    
    // Vertices:
    // 0: (-1, -3)
    // 1: ( 3,  1)
    // 2: (-1,  1)
    // Wait, let's use the standard one:
    // (-1, -1), (3, -1), (-1, 3) 
    // or
    // (-1, 1), (-1, -3), (3, 1)
    
    // Original was:
    // vec2<f32>(-1.0, -3.0),
    // vec2<f32>( 3.0,  1.0),
    // vec2<f32>(-1.0,  1.0),
    
    // Let's trace it:
    // (-1, -3) -> Bottom Left, way down
    // (3, 1) -> Top Right, way right
    // (-1, 1) -> Top Left
    // This covers (-1,-1) to (1,1) if CCW.
    // (-1,-3) -> (-1,1) -> (3,1) is clockwise?
    // -1, -3
    // -1,  1
    //  3,  1
    // Cross product: (0, 4) x (4, 0) -> z is negative?
    // Let's stick to standard full screen triangle:
    // (-1, -1), (3, -1), (-1, 3) -> UV: (0, 1), (2, 1), (0, -1)
    
    // Let's use the index to generate
    var uv = vec2<f32>(f32((vertex_index << 1u) & 2u), f32(vertex_index & 2u));
    var pos = vec2<f32>(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0); // flip y for NDC if needed
    
    // Correction:
    // index 0: uv(0,0) -> pos(-1, 1)  (Top Left)
    // index 1: uv(2,0) -> pos( 3, 1)  (Top Right, far)
    // index 2: uv(0,2) -> pos(-1,-3)  (Bottom Left, far)
    
    var output: VertexOutput;
    output.position = vec4<f32>(pos, 0.0, 1.0);
    output.uv = uv;

    return output;
}