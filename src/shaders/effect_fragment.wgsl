struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

fn grid(uv: vec2<f32>, grid_size: f32) -> vec4<f32> {
    // 2. SCALE AND REPEAT
    // Multiply by 8.0 to get 8 cells
    // fract() discards the integer, leaving 0.0 -> 0.99 repeating
    let tile_uv = fract(uv * grid_size);

    // Standard edge distance logic
    let edge = min(
        min(tile_uv.x, 1.0 - tile_uv.x),
        min(tile_uv.y, 1.0 - tile_uv.y),
    );
    
    // Make line thickness consistent regardless of grid scale
    let grid_thickness = 0.05; 
    let grid_mask = step(edge, grid_thickness);
    
    let grid_color = vec4<f32>(0.3, 0.3, 0.3, 1.0);
    let base = vec4<f32>(0.0, 0.0, 0.0, 1.0);

    return mix(base, grid_color, grid_mask);
}

@fragment
fn main(in: VertexOutput) -> @location(0) vec4<f32> {
    let grid_color = grid(in.uv, 8.0);

    return grid_color;
}
