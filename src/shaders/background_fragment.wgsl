struct VertexOutput {
  @builtin(position) position: vec4<f32>,
  @location(0) uv: vec2<f32>,
};

fn hash12(p: vec2<f32>) -> f32 {
  var p3 = fract(vec3<f32>(p.xyx) * .1031);
  p3 += dot(p3, p3.yzx + 33.33);

  return fract((p3.x + p3.y) * p3.z);
}

fn star_layer(uv: vec2<f32>, scale: f32, density: f32) -> f32 {
  let grid_uv = uv * scale;
  let grid_id = floor(grid_uv);
  let local_uv = fract(grid_uv) - 0.5;

  let rand = hash12(grid_id);
 
  if (rand > density) {
      return 0.0;
  }
 
  let offset = vec2<f32>(
    hash12(grid_id + vec2<f32>(12.34, 56.78)) - 0.5,
    hash12(grid_id + vec2<f32>(90.12, 34.56)) - 0.5
  );
 
  let brightness = hash12(grid_id + vec2<f32>(7.8, 9.0));
 
  let dist = length(local_uv - offset * 0.5);
 
  let size = 0.05 + brightness * 0.05;
  let star = max(0.0, 1.0 - dist / size);

  return pow(star, 4.0) * brightness;
}

@fragment
fn main(in: VertexOutput) -> @location(0) vec4<f32> {
  var color = vec3<f32>(0.02, 0.02, 0.06);
 
  let aspect = globals.screen_wh.x / globals.screen_wh.y;
  let screen_uv = (in.uv - 0.5) * vec2<f32>(aspect, 1.0) / globals.camera_zoom;
 
  let cam_pos = globals.camera_xy.xy;
  let zoom = globals.camera_zoom;

  // fade out layers as we zoom out (zoom value decreases)
  let fade1 = smoothstep(0.1, 0.4, zoom);
  let fade2 = smoothstep(0.3, 0.8, zoom);
  let fade3 = smoothstep(0.05, 0.2, zoom);
 
  let uv1 = screen_uv + cam_pos * 0.001;
  color += vec3<f32>(1.0) * star_layer(uv1, 20.0, 0.2) * fade1;
 
  let uv2 = screen_uv + cam_pos * 0.003;
  color += vec3<f32>(0.8, 0.8, 1.0) * star_layer(uv2, 40.0, 0.1) * fade2;
 
  let uv3 = screen_uv + cam_pos * 0.005;
  color += vec3<f32>(0.9, 0.9, 0.7) * star_layer(uv3, 10.0, 0.02) * fade3;

  return vec4<f32>(color, 1.0);
}
