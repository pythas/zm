const std = @import("std");

var prng: std.Random.DefaultPrng = undefined;
var seeded = false;

pub fn init(seed: u64) void {
    prng = std.Random.DefaultPrng.init(seed);
    seeded = true;
}

pub fn random() std.Random {
    std.debug.assert(seeded);
    return prng.random();
}
