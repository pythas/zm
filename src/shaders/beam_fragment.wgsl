struct FragmentInput {
  @builtin(position) position: vec4<f32>,
  @location(0) uv: vec2<f32>,
};

@fragment
fn main(input: FragmentInput) -> @location(0) vec4<f32> {
  let u_coord = input.uv.x; // along the beam
  let v_coord = input.uv.y; // across the beam (0..1, center at 0.5)

  let current_time = globals.t;
  let normalized_distance = (v_coord - 0.5) * 2.0;
  let distance_from_center = abs(normalized_distance);

  let pulse_factor = 0.5 + 0.5 * sin(current_time * 8.0);
  
  let core_width = 0.10 - 0.03 * pulse_factor;
  let glow_width = 0.45 + 0.10 * pulse_factor;

  let start_fade = smoothstep(0.00, 0.10, u_coord);
  let end_fade = 1.0 - smoothstep(0.80, 1.00, u_coord);
  let length_mask = start_fade * end_fade;

  let core_intensity_base = smoothstep(core_width, 0.0, distance_from_center) * length_mask;
  let glow_intensity_base = smoothstep(glow_width, 0.0, distance_from_center) * length_mask;

  let muzzle_length = 0.20;
  let muzzle_factor = 1.0 - smoothstep(0.0, muzzle_length, u_coord);
  let muzzle_glow_intensity = muzzle_factor * exp(-distance_from_center * 8.0);

  let flicker_factor = 0.7 + 0.3 * sin(u_coord * 40.0 + current_time * 25.0);

  let core_color = vec3<f32>(3.0, 2.6, 2.2);   // white-hot
  let glow_color = vec3<f32>(2.0, 0.8, 0.3);   // tangerine
  let outer_color = vec3<f32>(1.0, 0.25, 0.15); // red
  let muzzle_color = vec3<f32>(4.0, 3.0, 2.5);  // super bright at origin

  let core_intensity = core_intensity_base * (0.8 + 0.4 * pulse_factor) * flicker_factor;
  let glow_intensity = glow_intensity_base * (0.4 + 0.3 * pulse_factor);
  let outer_intensity = smoothstep(1.0, 0.0, distance_from_center) * 0.2 * length_mask;

  var final_color = vec3<f32>(0.0);
  final_color += core_intensity * core_color;
  final_color += glow_intensity * glow_color;
  final_color += outer_intensity * outer_color;
  final_color += muzzle_glow_intensity * muzzle_color;

  let final_alpha = clamp(core_intensity + glow_intensity + muzzle_glow_intensity * 0.8, 0.0, 1.0);
  final_color = final_color * 0.6;

  return vec4<f32>(final_color, final_alpha);
}
