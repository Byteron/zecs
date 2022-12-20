const std = @import("std");
const entities = @import("entities.zig");
const Entities = entities.Entities;
const System = *const fn (*World) anyerror!void;
const StructField = std.builtin.Type.StructField;

fn Query(comptime types: anytype, comptime filter: anytype) type {
    const TT = @TypeOf(types);
    const FT = @TypeOf(filter);
    const types_info = @typeInfo(TT);
    const filter_info = @typeInfo(FT);

    if (types_info != .Struct or filter_info != .Struct) {
        @compileError("invalid types for query\n");
    }

    var fields: []const StructField = &[0]StructField{};

    inline for (types) |T| {
        var name: []const u8 = undefined;
        var FieldType: type = undefined;

        if (T == System) {
            name = "System";
            FieldType = System;
        } else {
            var type_name = @typeName(T);
            var split = std.mem.splitBackwards(u8, type_name, ".");
            var last = split.next().?;
            name = last;
            FieldType = *T;
        }

        // @compileLog(name);
        // @compileLog(T);

        fields = fields ++ [_]StructField{.{
            .name = name,
            .field_type = FieldType,
            .is_comptime = false,
            .alignment = @alignOf(T),
            .default_value = null,
        }};
    }

    const Element = @Type(.{ .Struct = .{
        .layout = .Auto,
        .is_tuple = false,
        .fields = fields,
        .decls = &[_]std.builtin.Type.Declaration{},
    } });

    return struct {
        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            _ = allocator;
            return .{};
        }

        pub fn next(self: *Self) ?Element {
            _ = self;
            return null;
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

    pub fn addSystem(self: *World, system: System) !void {
        const entity = try self.entities.spawn();
        try self.entities.set(System, entity, system);
    }

    pub fn query(self: *World, comptime types: anytype) Query(types, .{}) {
        return Query(types, .{}).init(self.allocator);
    }

    pub fn run(self: *World) !void {
        var q = self.query(.{System});
        while (q.next()) |e| {
            try e.System(self);
        }
    }
};

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

    try world.addSystem(testSystem);

    try world.run();
    try world.run();
}

fn testSystem(world: *World) !void {
    var query = world.query(.{ Position, Velocity });

    while (query.next()) |e| {
        e.Position.x += e.Velocity.x;
        e.Position.y += e.Velocity.y;
    }

    std.debug.print("hello from testSystem\n", .{});
}
