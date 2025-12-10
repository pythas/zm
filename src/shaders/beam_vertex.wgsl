struct VertexInput {
  @location(0) start_pos: vec2<f32>,
  @location(1) end_pos: vec2<f32>,
  @location(2) width: f32,
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

  let quad: array<vec2<f32>, 6> = array(
      vec2<f32>(0.0, 0.0),
      vec2<f32>(1.0, 0.0),
      vec2<f32>(0.0, 1.0),

      vec2<f32>(0.0, 1.0),
      vec2<f32>(1.0, 0.0),
      vec2<f32>(1.0, 1.0),
  );

  let uv = quad[vertex_index];
  output.uv = uv;

  let start_pos = input.start_pos;
  let end_pos = input.end_pos;
  let beam_width = input.width;

  let direction_vec = end_pos - start_pos;
  let beam_length = length(direction_vec);
  let normalized_dir = direction_vec / beam_length;
  let normal_vec = vec2<f32>(-normalized_dir.y, normalized_dir.x);

  let u_coord = uv.x;
  let v_coord = (uv.y - 0.5) * beam_width;

  let world_pos = start_pos + normalized_dir * (u_coord * beam_length) + normal_vec * v_coord;
  let ndc_pos = world_to_ndc(world_pos);
  output.position = vec4<f32>(ndc_pos, 0.0, 1.0);
  return output;
}
