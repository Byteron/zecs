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

    try world.add(Position{ .x = 10, .y = 15});
    try world.add(Velocity{ .x = 5, .y = 0});

    var pos = try world.get(Position, 0);
    var vel = try world.get(Velocity, 0);

    std.debug.print("{}\n", .{pos});
    std.debug.print("{}\n", .{vel});
}