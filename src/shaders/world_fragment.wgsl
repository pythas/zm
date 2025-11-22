@group(0) @binding(2) var atlas_texture: texture_2d_array<f32>;
@group(0) @binding(3) var atlas_sampler: sampler;

@group(1) @binding(0) var<uniform> chunk_uniforms: ChunkUniforms;
@group(1) @binding(1) var tilemap_texture: texture_2d<u32>;

fn fetch_tile(tile_pos: vec2<f32>) -> Tile {
    let tx = clamp(i32(floor(tile_pos.x)), 0, CHUNK_W - 1);
    let ty = clamp(i32(floor(tile_pos.y)), 0, CHUNK_H - 1);

    let id = textureLoad(tilemap_texture, vec2<i32>(tx, ty), 0).r;
    return unpack_tile(id);
}

struct FragmentInput {
    @location(0) tile_pos: vec2<f32>,
};

@fragment
fn main(input: FragmentInput) -> @location(0) vec4<f32> {
    let tile = fetch_tile(input.tile_pos);

    if (tile.category == 0u) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }

    let tile_uv = fract(input.tile_pos);
    let uv = get_sprite_uv(tile, tile_uv);
    let color = textureSampleLevel(atlas_texture, atlas_sampler, uv, tile.sheet, 0.0);
    
    return color;
}
