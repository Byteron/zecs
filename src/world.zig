const std = @import("std");
const entities = @import("entities.zig");
const Entities = entities.Entities;
const ComponentType = entities.ComponentType;
const Table = entities.Table;
const System = *const fn (*World) anyerror!void;
const StructField = std.builtin.Type.StructField;

fn IterResult(comptime types: anytype) type {
    const Types = @TypeOf(types);
    const types_fields = std.meta.fields(Types);
    var fields: []const StructField = &[0]StructField{};

    inline for (types_fields) |field| {
        const T = @field(types, field.name);

        fields = fields ++ [_]StructField{.{
            .name = field.name,
            .type = *T,
            .is_comptime = false,
            .alignment = @alignOf(T),
            .default_value = undefined,
        }};
    }

    return @Type(.{ .Struct = .{
        .layout = .Auto,
        .is_tuple = false,
        .fields = fields,
        .decls = &[_]std.builtin.Type.Declaration{},
    } });
}

const AccessModifier = enum {
    read,
    write,
};

fn Iter(comptime types: anytype, comptime filter: anytype) type {
    const Types = @TypeOf(types);
    const fields = std.meta.fields(Types);

    const AccessInfo = struct {
        mod: AccessModifier,
        type: type,
        name: []const u8,
    };

    comptime var array = [_]AccessInfo{undefined} ** fields.len;

    inline for (fields) |field, i| {
        const T = @field(types, field.name);
        array[i] = AccessInfo{
            .type = T,
            .name = field.name,
            .mod = .read,
        };
    }

    return struct {
        const Self = @This();

        query: *Query(types, filter),

        table_index: u32 = 0,
        row_index: u32 = 0,

        pub fn next(self: *Self) ?IterResult(types) {
            var tables = self.query.tables;

            if (self.table_index == tables.items.len) return null;

            var table = tables.items[self.table_index];

            if (self.row_index < table.len) {
                var value = IterResult(types){};
                inline for (array) |info| {
                    var storage = table.getStorage(info.type) orelse unreachable;
                    @field(value, info.name) = &storage[self.row_index];
                }
                self.row_index += 1;
                return value;
            }

            self.row_index = 0;
            self.table_index += 1;

            while (self.table_index < tables.items.len and tables.items[self.table_index].len == 0) {
                self.table_index += 1;
            }

            return self.next();
        }
    };
}

fn Query(comptime types: anytype, comptime filter: anytype) type {
    const Types = @TypeOf(types);
    const Filter = @TypeOf(filter);
    const types_info = @typeInfo(Types);
    const filter_info = @typeInfo(Filter);

    if (types_info != .Struct or filter_info != .Struct) {
        @compileError("invalid types for query\n");
    }

    return struct {
        const Self = @This();

        entities: *Entities,
        tables: std.ArrayListUnmanaged(*Table) = .{},

        pub fn init(allocator: std.mem.Allocator, es: *Entities) !Self {
            var query = Self{
                .entities = es,
            };

            for (es.tables.items) |*table| {
                var matches = true;
                const fields = std.meta.fields(Types);

                inline for (fields) |field| {
                    const T = @field(types, field.name);
                    const component_type = ComponentType.init(T);
                    if (!table.containsType(component_type)) matches = false;
                }
                if (!matches) continue;
                try query.tables.append(allocator, table);
            }
            return query;
        }

        pub fn deinit(self: *Self) void {
            self.tables.deinit(self.entities.allocator);
        }

        pub fn iter(self: *Self) Iter(types, filter) {
            return Iter(types, filter){
                .query = self,
            };
        }

        pub fn getTables(self: *Self) []*Table {
            return self.tables.items;
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

    pub fn query(self: *World, comptime types: anytype) !Query(types, .{}) {
        return try Query(types, .{}).init(self.allocator, &self.entities);
    }

    pub fn run(self: *World) !void {
        var q = try self.query(.{ .system = System });
        defer q.deinit();

        var it = q.iter();
        while (it.next()) |e| {
            try e.system.*(self);
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

    const e1 = try world.entities.spawn();
    try world.entities.set(Position, e1, .{ .x = 0, .y = 5 });
    try world.entities.set(Velocity, e1, .{ .x = 5, .y = 5 });

    const e2 = try world.entities.spawn();
    try world.entities.set(Position, e2, .{ .x = 4, .y = 5 });
    try world.entities.set(Velocity, e2, .{ .x = 7, .y = 4 });

    const e3 = try world.entities.spawn();
    try world.entities.set(Position, e3, .{ .x = 5, .y = 5 });

    try world.addSystem(testSystem);

    try world.run();
    try world.run();
}

fn testSystem(world: *World) !void {
    var query = try world.query(.{ .pos = Position, .vel = Velocity });
    defer query.deinit();

    var it = query.iter();
    while (it.next()) |e| {
        e.pos.x += e.vel.x;
        e.pos.y += e.vel.y;
        std.debug.print("Changed Position: ({},{})\n", .{ e.pos.x, e.pos.y });
    }

    std.debug.print("hello from testSystem\n", .{});
}
