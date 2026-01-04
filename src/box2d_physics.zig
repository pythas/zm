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
    default,
    debris,
};

pub const TileData = struct {
    pos: Vec2,
    half_width: f32,
    half_height: f32,
    density: f32,
    layer: CollisionLayer = .default,
};

pub const RayHit = struct {
    point: Vec2,
    normal: Vec2,
    fraction: f32,
    hit: bool,
    body_id: BodyId,
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
        c.b2World_Step(self.world_id, dt, 4);
    }

    const RayCastContext = struct {
        result: *RayHit,
        ignore_body: BodyId,
    };

    fn rayCastCallback(
        shape_id: c.b2ShapeId,
        point: c.b2Vec2,
        normal: c.b2Vec2,
        fraction: f32,
        context: ?*anyopaque,
    ) callconv(.C) f32 {
        const ctx: *RayCastContext = @ptrCast(@alignCast(context));
        const hit_body_id = c.b2Shape_GetBody(shape_id);

        if (ctx.ignore_body.isValid()) {
            const id1 = hit_body_id;
            const id2 = ctx.ignore_body.id;
            if (id1.index1 == id2.index1 and id1.generation == id2.generation and id1.world0 == id2.world0) {
                return -1.0;
            }
        }

        ctx.result.hit = true;
        ctx.result.fraction = fraction;
        ctx.result.point = Vec2.init(point.x, point.y);
        ctx.result.normal = Vec2.init(normal.x, normal.y);
        ctx.result.body_id = BodyId{ .id = hit_body_id };
        return fraction;
    }

    pub fn castRay(self: *Self, origin: Vec2, end_pos: Vec2, ignore_body: ?BodyId) RayHit {
        const translation = end_pos.sub(origin);
        var filter = c.b2DefaultQueryFilter();
        filter.categoryBits = 0x0001;
        filter.maskBits = 0xFFFFFFFF;

        var result: RayHit = undefined;
        result.hit = false;
        result.fraction = 1.0;
        result.point = end_pos;
        result.normal = Vec2.init(0, 0);
        result.body_id = BodyId.invalid;

        var context = RayCastContext{
            .result = &result,
            .ignore_body = ignore_body orelse BodyId.invalid,
        };

        _ = c.b2World_CastRay(
            self.world_id,
            c.b2Vec2{ .x = origin.x, .y = origin.y },
            c.b2Vec2{ .x = translation.x, .y = translation.y },
            filter,
            rayCastCallback,
            &context,
        );

        return result;
    }

    pub fn createBody(
        self: *Self,
        pos: Vec2,
        rotation: f32,
        linear_damping: f32,
        angular_damping: f32,
    ) !BodyId {
        var body_def = c.b2DefaultBodyDef();
        body_def.position = c.b2Vec2{ .x = pos.x, .y = pos.y };
        body_def.rotation = c.b2MakeRot(rotation);
        body_def.type = c.b2_dynamicBody;
        body_def.linearDamping = linear_damping;
        body_def.angularDamping = angular_damping;

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

    pub fn addLinearImpulseAtPoint(self: *Self, body_id: BodyId, impulse: Vec2, point: Vec2, wake: bool) void {
        _ = self;
        if (!body_id.isValid()) return;

        c.b2Body_ApplyLinearImpulse(body_id.id, c.b2Vec2{ .x = impulse.x, .y = impulse.y }, c.b2Vec2{ .x = point.x, .y = point.y }, wake);
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

    pub fn createTileShape(self: *Self, body_id: BodyId, tiles: []const TileData) !void {
        _ = self;
        if (!body_id.isValid()) return;

        for (tiles) |tile| {
            var shape_def = c.b2DefaultShapeDef();
            shape_def.density = tile.density;

            switch (tile.layer) {
                .default => {
                    shape_def.filter.categoryBits = 0x0001;
                    shape_def.filter.maskBits = 0xFFFFFFFF;
                },
                .debris => {
                    shape_def.filter.categoryBits = 0x0002;
                    shape_def.filter.maskBits = 0x0000;
                },
            }

            const hx = tile.half_width;
            const hy = tile.half_height;
            const box = c.b2MakeOffsetBox(hx, hy, c.b2Vec2{ .x = tile.pos.x, .y = tile.pos.y }, c.b2MakeRot(0.0));

            _ = c.b2CreatePolygonShape(body_id.id, &shape_def, &box);
        }
    }
};
