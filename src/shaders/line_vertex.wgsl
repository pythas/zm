struct VertexInput {
  @location(0) start_pos: vec2<f32>,
  @location(1) end_pos: vec2<f32>,
  @location(2) color: vec4<f32>,
  @location(3) thickness: f32,
  @location(4) dash_scale: f32,
};

struct VertexOutput {
  @builtin(position) position: vec4<f32>,
  @location(0) uv: vec2<f32>,
  @location(1) color: vec4<f32>,
  @location(2) dash_scale: f32,
  @location(3) line_len: f32,
};

@vertex
fn main(
  @builtin(vertex_index) vertex_index: u32,
  input: VertexInput,
) -> VertexOutput {
  var output: VertexOutput;

  let quad: array<vec2<f32>, 6> = array(
      vec2<f32>(0.0, -0.5),
      vec2<f32>(1.0, -0.5),
      vec2<f32>(0.0,  0.5),

      vec2<f32>(0.0,  0.5),
      vec2<f32>(1.0, -0.5),
      vec2<f32>(1.0,  0.5),
  );

  let local_uv = quad[vertex_index]; // x: 0..1 (along line), y: -0.5..0.5 (across)
  
  let diff = input.end_pos - input.start_pos;
  let len = length(diff);
  let dir = diff / len;
  let normal = vec2<f32>(-dir.y, dir.x);
  
  let width = input.thickness;
  
  let pos = input.start_pos + (dir * local_uv.x * len) + (normal * local_uv.y * width);
  
  let ndc_pos = world_to_ndc(pos);

  output.position = vec4<f32>(ndc_pos, 0.0, 1.0);
  output.uv = local_uv;
  output.color = input.color;
  output.dash_scale = input.dash_scale;
  output.line_len = len;

  return output;
}
