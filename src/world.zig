const std = @import("std");
const entities = @import("entities.zig");
const Entities = entities.Entities;
const System = *const fn (*World) anyerror!void;

fn Query(comptime types: anytype, comptime filter: anytype) type {
    const TT = @TypeOf(types);
    const FT = @TypeOf(filter);
    const types_info = @typeInfo(TT);
    const filter_info = @typeInfo(FT);

    _ = types_info;
    _ = filter_info;

    return struct {
        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            _ = allocator;
            return .{};
        }

        pub fn run(self: *Self, world: *World) void {
            _ = self;
            _ = world;
        }
    };
}

const World = struct {
    allocator: std.mem.Allocator,

    entities: Entities,

    pub fn init(allocator: std.mem.Allocator) !World {
        return .{
            .allocator = allocator,
            .entities = try Entities.init(allocator),
        };
    }

    pub fn deinit(self: *World) void {
        self.entities.deinit();
    }

    pub fn add_system(self: *World, system: System) !void {
        const entity = try self.entities.spawn();
        try self.entities.set(System, entity, system);
    }

    pub fn query(self: *World, comptime types: anytype, comptime filter: anytype) Query(types, filter) {
        return Query(types, filter).init(self.allocator);
    }

    pub fn run(self: *World) !void {
        var q = self.query(.{System}, .{});
        q.run(self);
    }
};

const Position = struct {};
const Velocity = struct {};
const Active = struct {};
const Team1 = struct {};
const Team2 = struct {};
const Team3 = struct {};

test "world" {
    var world = try World.init(std.testing.allocator);
    defer world.deinit();

    try world.add_system(test_system1);
    try world.add_system(test_system2);

    try world.run();
    try world.run();
}

fn test_system1(world: *World) !void {
    const query = world.query(.{ Position, Velocity }, .{ .has = .{Active}, .not = .{ Team2, Team3 } });
    
    query.run(fn (positions: []Position, velocities: []Velocity) anyerror!void {
        for (positions, velocities, 0..) |pos, vel, i| {
            pos.x += vel.x;
            pos.y += vel.y;
            _ = i;
        }
    });
    
    std.debug.print("test system 1!\n", .{});
}

fn test_system2(world: *World) !void {
    _ = world;
    std.debug.print("test system 2!\n", .{});
}
