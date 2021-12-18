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

    const entity1 = world.spawn();
    const entity2 = world.spawn();

    try world.add(entity1, Position{ .x = 0, .y = 0});
    try world.add(entity1, Velocity{ .x = 5, .y = 0});

    try world.add(entity2, Position{ .x = 20, .y = 20});
    try world.add(entity2, Velocity{ .x = -5, .y = 0});

    world.query(.{Position, Velocity});
    
    print_entity(&world, entity1);
    print_entity(&world, entity2);
}

fn print_entity(world: *ecs.World, entity: usize) void {
    var pos = try world.get(Position, entity);
    var vel = try world.get(Velocity, entity);

    std.debug.print("Entity: {}\n{}\n{}\n", .{entity, pos, vel});
}