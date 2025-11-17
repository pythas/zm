const CHUNK_W = 64;
const CHUNK_H = 64;

struct GlobalUniforms {
    screen_wh: vec4<f32>,
    dt: f32,
    t: f32,
    tile_size: f32,
    _pad0: f32,
};

struct ChunkUniforms {
    chunk_xy: vec4<f32>,
    chunk_wh: vec4<f32>,
};

struct Tile {
    kind: u32,
    texture: u32,
};

@group(0) @binding(0) var<uniform> global_u: GlobalUniforms;
@group(0) @binding(1) var u_sampler: sampler;
@group(0) @binding(2) var u_atlas: texture_2d_array<f32>;

@group(1) @binding(0) var<uniform> chunk_u: ChunkUniforms;
@group(1) @binding(1) var u_tilemap: texture_2d<u32>;

const CHUNK_W_I: i32 = 64;
const CHUNK_H_I: i32 = 64;

fn fetch_tile(local_tile: vec2<f32>) -> Tile {
    let tx = clamp(i32(floor(local_tile.x)), 0, CHUNK_W_I - 1);
    let ty = clamp(i32(floor(local_tile.y)), 0, CHUNK_H_I - 1);

    let byte = textureLoad(u_tilemap, vec2<i32>(tx, ty), 0).r;
    let kind = (byte >> 4u) & 0xFu;
    let texture = byte & 0xFu;

    return Tile(kind, texture);
}

struct FSIn {
    @location(0) local_tile: vec2<f32>,
};

@fragment
fn main(in: FSIn) -> @location(0) vec4<f32> {
    let tile = fetch_tile(in.local_tile);

    if (tile.kind == 0u) {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0); // empty
    } else {
        return vec4<f32>(1.0, 1.0, 1.0, 1.0); // stone
    }
}
