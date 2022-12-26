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

const Health = struct {
    max: u32,
    value: u32,
};

test "world" {
    var world = try World.init(std.testing.allocator);
    defer world.deinit();

    _ = world.spawn()
        .set(Position{ .y = 5 })
        .set(Velocity{ .x = 5, .y = 5 });

    _ = world.spawn()
        .set(Position{ .x = 4, .y = 5 })
        .set(Velocity{ .x = 7, .y = 4 });

    _ = world.spawn()
        .set(Position{ .x = 5, .y = 5 });

    var index: u32 = 0;
    while (index < 10) : (index += 1) {
        try testSystem(&world);
        try emptySystem(&world);
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

fn emptySystem(world: *World) !void {
    var query = try world.query(.{ .pos = Position, .vel = Velocity, .health = Health });

    var it = query.iter();
    while (it.next()) |e| {
        e.pos.x += e.vel.x;
        e.pos.y += e.vel.y;
        e.health.value = e.health.max;
    }

    std.debug.print("hello from emptySystem\n", .{});
}
