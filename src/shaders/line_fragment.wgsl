struct FragmentInput {
  @location(0) uv: vec2<f32>,
  @location(1) color: vec4<f32>,
  @location(2) dash_scale: f32,
  @location(3) line_len: f32,
};

@fragment
fn main(input: FragmentInput) -> @location(0) vec4<f32> {
  var alpha = input.color.a;
  
  if (input.dash_scale > 0.01) {
      let pattern = sin(input.uv.x * input.line_len * input.dash_scale);
      if (pattern < 0.0) {
          discard;
      }
  }

  // Simple anti-aliasing across the line
  let edge_fade = 1.0 - smoothstep(0.4, 0.5, abs(input.uv.y));
  
  return vec4<f32>(input.color.rgb, alpha * edge_fade);
}
