struct VertexInput {
  @location(0) position: vec2<f32>,
  @location(1) uv: vec2<f32>,
  @location(2) color: vec4<f32>,
};

struct VertexOutput {
  @builtin(position) position: vec4<f32>,
  @location(1) uv: vec2<f32>,
  @location(2) color: vec4<f32>,
};

@vertex
fn main(
  input: VertexInput,
) -> VertexOutput {
  var out: VertexOutput;

  let screen = globals.screen_wh.xy;
  let px = (input.position.x / screen.x) * 2.0 - 1.0;
  let py = 1.0 - (input.position.y / screen.y) * 2.0;

  out.position = vec4<f32>(px, py, 0.0, 1.0);
  out.uv = input.uv;
  out.color = input.color;

  return out;
}
