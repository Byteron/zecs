const std = @import("std");
const ecs = @import("entities.zig");

const Position = struct {
    x: i32 = 0,
    y: i32 = 0,
};

const Velocity = struct {
    x: i32 = 0,
    y: i32 = 0,
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const alloc = gpa.allocator();

pub fn main() anyerror!void {
    var world = ecs.World.init(alloc);
    defer world.deinit();

    try setup(&world);
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

