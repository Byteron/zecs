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
    try world.add(entity1, Position{ .x = 0, .y = 0});
    try world.add(entity1, Velocity{ .x = 5, .y = 0});
    
    const entity2 = world.spawn();
    try world.add(entity2, Position{ .x = 20, .y = 20});
    try world.add(entity2, Velocity{ .x = -5, .y = 0});
    
    const entity3 = world.spawn();
    try world.add(entity3, Position{ .x = 30, .y = 30});

    world.remove(Position, entity2);

    const pv_query = try world.query(.{Position, Velocity});
    const v_query = try world.query(.{Velocity});
    const p_query = try world.query(.{Position});

    for (pv_query) |entity| {
        std.debug.print("Entity {}\n", .{entity});
    }
    
    for (v_query) |entity| {
        std.debug.print("Entity {}\n", .{entity});
    }

    for (p_query) |entity| {
        std.debug.print("Entity {}\n", .{entity});
    }
}