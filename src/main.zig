const std = @import("std");
const ecs = @import("ecs.zig");

const Position = struct {
    x: i32 = 0,
    y: i32 = 0,
};

const Velocity = struct {
    x: i32 = 0,
    y: i32 = 0,
};

pub fn main() anyerror!void {
    var world = ecs.World.init();
    defer world.deinit();

    try setup(&world);

    try physics(&world);
    try physics(&world);
    try physics(&world);
    try physics(&world);

    try print(&world);
}

fn setup(world: *ecs.World) !void {
    const entity1 = world.spawn();
    try world.add(entity1, Position{ .x = 0, .y = 0});
    try world.add(entity1, Velocity{ .x = 5, .y = 0});
    
    const entity2 = world.spawn();
    try world.add(entity2, Position{ .x = 0, .y = 0});
    try world.add(entity2, Velocity{ .x = -5, .y = 0});
    
    const entity3 = world.spawn();
    try world.add(entity3, Position{ .x = 0, .y = 0});
    try world.add(entity3, Velocity{ .x = 0, .y = 5});

    const entity4 = world.spawn();
    try world.add(entity4, Position{ .x = 0, .y = 0});
    try world.add(entity4, Velocity{ .x = 0, .y = -5});
}

fn physics(world: *ecs.World) !void {
    var query = try world.query(.{Position, Velocity});

    for (query) |entity| {
        const vel = try world.get(Velocity, entity);
        var pos = try world.get(Position, entity);

        pos.x += vel.x;
        pos.y += vel.y;
    }
}

fn print(world: *ecs.World) !void {
    const query = try world.query(.{Position, Velocity});

    for (query) |entity| {
        const vel = try world.get(Velocity, entity);
        const pos = try world.get(Position, entity);

        std.debug.print("Entity {}, {}, {}\n", .{entity, pos, vel});
    }
}