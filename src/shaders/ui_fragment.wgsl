struct VertexInput {
  @builtin(position) position: vec4<f32>,
  @location(1) uv: vec2<f32>,
  @location(2) color: vec4<f32>,
};

@fragment
fn main(
  input: VertexInput
) -> @location(0) vec4<f32> {
    return input.color;
}
