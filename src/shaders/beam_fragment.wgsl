struct FragmentInput {
  @builtin(position) position: vec4<f32>,
  @location(0) uv: vec2<f32>,
};

@fragment
fn main(input: FragmentInput) -> @location(0) vec4<f32> {
  let u = input.uv.x;
  let v = (input.uv.y - 0.5) * 2.0;

  let shape_width = max(0.0, 1.0 - u);
 
  let dist = abs(v);
  let core_zone = step(dist, shape_width * 0.3);

  let white_mask = step(dist, shape_width * 0.4) * step(u, 0.3);
  let yellow_mask = step(dist, shape_width * 0.7) * step(u, 0.7);
  let red_mask = step(dist, shape_width);
 
  var color = vec3<f32>(0.0);
  var alpha = 0.0;
 
  if (white_mask > 0.5) {
    color = vec3<f32>(1.0, 1.0, 1.0);
    alpha = 1.0;
  } else if (yellow_mask > 0.5) {
    color = vec3<f32>(1.0, 0.8, 0.2);
    alpha = 1.0;
  } else if (red_mask > 0.5) {
    color = vec3<f32>(0.9, 0.3, 0.1);
    alpha = 1.0;
  }
 
  let time = globals.t;
  let flicker = floor(sin(time * 20.0) * 2.0) * 0.05;
 
  if (u > (1.0 + flicker) * 0.9) {
    alpha = 0.0;
  }

  return vec4<f32>(color, alpha);
}
