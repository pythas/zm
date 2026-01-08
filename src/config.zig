const std = @import("std");

pub const world = struct {
    pub const chunk_size: f32 = 512.0;
    pub const unload_dist_chunks: f32 = 6.0;
    pub const spawn_range_chunks: i32 = 4;
};

pub const combat = struct {
    pub const max_targeting_range: f32 = 500.0;
    pub const laser_cooldown: f32 = 1.0;
    pub const laser_raycast_step: f32 = 4.0;
    pub const railgun_raycast_step: f32 = 4.0;
    pub const railgun_trail_lifetime: f32 = 0.5;
    pub const laser_beam_lifetime: f32 = 0.2;
};

pub const ui = struct {
    pub const radar_range: f32 = 1000.0;
    pub const radar_size: f32 = 200.0;
    pub const radar_padding: f32 = 20.0;
    pub const radar_blip_size: f32 = 2.0;
    pub const radar_player_blip_size: f32 = 3.0;
    
    pub const notification_auto_dismiss_time: f32 = 3.0;
};

pub const physics = struct {
    pub const linear_damping: f32 = 0.5;
    pub const angular_damping: f32 = 2.0;
};

pub const assets = struct {
    pub const font = "assets/spleen-6x12.bdf";
    pub const asteroid = "assets/asteroid.png";
    pub const ship = "assets/ship.png";
    pub const resource = "assets/resource.png";
    pub const tool = "assets/tool.png";
    pub const recipe = "assets/recipe.png";
    pub const ship_json = "assets/ship.json";
};
