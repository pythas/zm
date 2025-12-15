const std = @import("std");
const Vec2 = @import("vec2.zig").Vec2;

const c = @cImport({
    @cInclude("box2d/box2d.h");
});

pub const BodyId = struct {
    const Self = @This();

    id: c.b2BodyId,

    pub const invalid = Self{ .id = c.b2_nullBodyId };

    pub fn isValid(self: Self) bool {
        return c.b2Body_IsValid(self.id);
    }
};

pub const CollisionLayer = enum {
    Default,
    Debris,
};

pub const TileData = struct {
    pos: Vec2,
    density: f32,
    layer: CollisionLayer = .Default,
};

pub const Physics = struct {
    const Self = @This();

    world_id: c.b2WorldId,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const world_def = c.b2DefaultWorldDef();
        var mut_world_def = world_def;
        mut_world_def.gravity = c.b2Vec2{ .x = 0.0, .y = 0.0 };

        const world_id = c.b2CreateWorld(&mut_world_def);

        return .{
            .world_id = world_id,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
        c.b2DestroyWorld(self.world_id);
    }

    pub fn update(self: *Self, dt: f32) void {
        // Box2D uses sub-stepping internally, we just call step once
        c.b2World_Step(self.world_id, dt, 4); // 4 sub-steps for stability
    }

    pub fn createBody(self: *Self, pos: Vec2, rotation: f32) !BodyId {
        var body_def = c.b2DefaultBodyDef();
        body_def.position = c.b2Vec2{ .x = pos.x, .y = pos.y };
        body_def.rotation = c.b2MakeRot(rotation);
        body_def.type = c.b2_dynamicBody;
        body_def.linearDamping = 0.05;
        body_def.angularDamping = 2.0;

        const body_id = c.b2CreateBody(self.world_id, &body_def);
        return BodyId{ .id = body_id };
    }

    pub fn destroyBody(self: *Self, body_id: BodyId) void {
        _ = self;
        if (body_id.isValid()) {
            c.b2DestroyBody(body_id.id);
        }
    }

    pub fn getPosition(self: *Self, body_id: BodyId) Vec2 {
        _ = self;
        if (!body_id.isValid()) return Vec2.init(0, 0);

        const pos = c.b2Body_GetPosition(body_id.id);
        return Vec2.init(pos.x, pos.y);
    }

    pub fn setPosition(self: *Self, body_id: BodyId, pos: Vec2) void {
        _ = self;
        if (!body_id.isValid()) return;

        const current_rot = c.b2Body_GetRotation(body_id.id);
        c.b2Body_SetTransform(body_id.id, c.b2Vec2{ .x = pos.x, .y = pos.y }, current_rot);
    }

    pub fn getRotation(self: *Self, body_id: BodyId) f32 {
        _ = self;
        if (!body_id.isValid()) return 0.0;

        const rot = c.b2Body_GetRotation(body_id.id);
        return c.b2Rot_GetAngle(rot);
    }

    pub fn setRotation(self: *Self, body_id: BodyId, angle: f32) void {
        _ = self;
        if (!body_id.isValid()) return;

        const current_pos = c.b2Body_GetPosition(body_id.id);
        c.b2Body_SetTransform(body_id.id, current_pos, c.b2MakeRot(angle));
    }

    pub fn addForce(self: *Self, body_id: BodyId, force: Vec2, wake: bool) void {
        _ = self;
        if (!body_id.isValid()) return;

        c.b2Body_ApplyForceToCenter(body_id.id, c.b2Vec2{ .x = force.x, .y = force.y }, wake);
    }

    pub fn addForceAtPoint(self: *Self, body_id: BodyId, force: Vec2, point: Vec2, wake: bool) void {
        _ = self;
        if (!body_id.isValid()) return;

        c.b2Body_ApplyForce(body_id.id, c.b2Vec2{ .x = force.x, .y = force.y }, c.b2Vec2{ .x = point.x, .y = point.y }, wake);
    }

    pub fn addTorque(self: *Self, body_id: BodyId, torque: f32, wake: bool) void {
        _ = self;
        if (!body_id.isValid()) return;

        c.b2Body_ApplyTorque(body_id.id, torque, wake);
    }

    pub fn setGravity(self: *Self, gravity: Vec2) void {
        c.b2World_SetGravity(self.world_id, c.b2Vec2{ .x = gravity.x, .y = gravity.y });
    }

    pub fn getWorldCenterOfMass(self: *Self, body_id: BodyId) Vec2 {
        _ = self;
        if (!body_id.isValid()) return Vec2.init(0, 0);

        const center = c.b2Body_GetWorldCenterOfMass(body_id.id);
        return Vec2.init(center.x, center.y);
    }

    pub fn getLinearVelocity(self: *Self, body_id: BodyId) Vec2 {
        _ = self;
        if (!body_id.isValid()) return Vec2.init(0, 0);

        const vel = c.b2Body_GetLinearVelocity(body_id.id);
        return Vec2.init(vel.x, vel.y);
    }

    pub fn setLinearVelocity(self: *Self, body_id: BodyId, velocity: Vec2) void {
        _ = self;
        if (!body_id.isValid()) return;

        c.b2Body_SetLinearVelocity(body_id.id, c.b2Vec2{ .x = velocity.x, .y = velocity.y });
    }

    pub fn getAngularVelocity(self: *Self, body_id: BodyId) f32 {
        _ = self;
        if (!body_id.isValid()) return 0.0;

        return c.b2Body_GetAngularVelocity(body_id.id);
    }

    pub fn setAngularVelocity(self: *Self, body_id: BodyId, velocity: f32) void {
        _ = self;
        if (!body_id.isValid()) return;

        c.b2Body_SetAngularVelocity(body_id.id, velocity);
    }

    // For creating compound shapes (tile ships)
    pub fn createTileShape(self: *Self, body_id: BodyId, tiles: []const TileData) !void {
        _ = self;
        if (!body_id.isValid()) return;

        for (tiles) |tile| {
            var shape_def = c.b2DefaultShapeDef();
            shape_def.density = tile.density;

            switch (tile.layer) {
                .Default => {
                    shape_def.filter.categoryBits = 0x0001;
                    shape_def.filter.maskBits = 0xFFFF;
                },
                .Debris => {
                    shape_def.filter.categoryBits = 0x0002;
                    shape_def.filter.maskBits = 0x0000; // Collides with nothing
                },
            }

            // Create a box fixture for each tile (4 unit radius = 8x8 tile)
            // Shrink slightly to prevent internal edge collisions and debris overlap
            const h = 4.0 - 0.05;
            const box = c.b2MakeOffsetBox(h, h, c.b2Vec2{ .x = tile.pos.x, .y = tile.pos.y }, c.b2MakeRot(0.0));

            _ = c.b2CreatePolygonShape(body_id.id, &shape_def, &box);
        }
    }
};

