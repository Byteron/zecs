const std = @import("std");
const testing = std.testing;

pub const Entities = @import("entities.zig").Enties;
pub const Entity = @import("entities.zig").Entity;
pub const World = @import("world.zig").World;
pub const System = @import("world.zig").System;

const Position = struct {
    x: i32 = 0,
    y: i32 = 0,
};

const Velocity = struct {
    x: i32 = 0,
    y: i32 = 0,
};

test "world" {
    var world = try World.init(std.testing.allocator);
    defer world.deinit();

    const e1 = try world.entities.spawn();
    try world.entities.set(Position, e1, .{ .x = 0, .y = 5 });
    try world.entities.set(Velocity, e1, .{ .x = 5, .y = 5 });

    const e2 = try world.entities.spawn();
    try world.entities.set(Position, e2, .{ .x = 4, .y = 5 });
    try world.entities.set(Velocity, e2, .{ .x = 7, .y = 4 });

    const e3 = try world.entities.spawn();
    try world.entities.set(Position, e3, .{ .x = 5, .y = 5 });

    try world.addSystem(testSystem);

    var index: u32 = 0;
    while (index < 10) : (index += 1) {
        try world.run();
    }
}

fn testSystem(world: *World) !void {
    var query = try world.query(.{ .pos = Position, .vel = Velocity });

    var it = query.iter();
    while (it.next()) |e| {
        e.pos.x += e.vel.x;
        e.pos.y += e.vel.y;
        std.debug.print("Changed Position: ({},{})\n", .{ e.pos.x, e.pos.y });
    }

    std.debug.print("hello from testSystem\n", .{});
}
