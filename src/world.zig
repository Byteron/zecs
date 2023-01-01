const std = @import("std");
const entities = @import("entities.zig");
const Entities = entities.Entities;
const Entity = entities.Entity;
const ComponentType = entities.ComponentType;
const Table = entities.Table;
const StructField = std.builtin.Type.StructField;
pub const System = *const fn (*World) anyerror!void;

pub fn IterResult(comptime types: anytype) type {
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

pub fn Cache(comptime types: anytype) type {
    const Types = @TypeOf(types);
    const types_fields = std.meta.fields(Types);
    var fields: []const StructField = &[0]StructField{};

    inline for (types_fields) |field| {
        const T = @field(types, field.name);
        fields = fields ++ [_]StructField{.{
            .name = field.name,
            .type = []T,
            .is_comptime = false,
            .alignment = @alignOf([]T),
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

pub fn Iter(comptime types: anytype, comptime filter: anytype) type {
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
        cache: Cache(types) = .{},

        table_index: u32 = 0,
        row_index: u32 = 0,

        pub fn init(query: *Query(types, filter)) Self {
            var it = Self{
                .query = query,
            };

            if (query.tables.items.len == 0) return it;
            var table = query.tables.items[0];
            inline for (array) |info| {
                @field(it.cache, info.name) = table.getStorage(info.type).?;
            }

            return it;
        }

        pub fn next(self: *Self) ?IterResult(types) {
            var tables = self.query.tables;

            if (self.table_index == tables.items.len) return null;

            var table = tables.items[self.table_index];

            if (self.row_index < table.len) {
                var value = IterResult(types){};
                inline for (array) |info| {
                    var storage = @field(self.cache, info.name);
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

            if (self.table_index == tables.items.len) return null;

            table = tables.items[self.table_index];

            if (self.row_index == table.len) return null;

            var value = IterResult(types){};
            inline for (array) |info| {
                @field(self.cache, info.name) = table.getStorage(info.type).?;
                var storage = @field(self.cache, info.name);
                @field(value, info.name) = &storage[self.row_index];
            }
            self.row_index += 1;
            return value;
        }
    };
}

pub const EntityBuilder = struct {
    entities: *Entities,
    entity: Entity,

    pub fn set(self: EntityBuilder, comptime T: type, component: T) EntityBuilder {
        self.entities.set(T, self.entity, component) catch unreachable;
        return self;
    }

    pub fn remove(self: EntityBuilder, comptime T: type) EntityBuilder {
        self.entities.remove(T, self.entity) catch unreachable;
        return self;
    }

    pub fn id(self: EntityBuilder) Entity {
        return self.entity;
    }
};

pub fn Query(comptime types: anytype, comptime filter: anytype) type {
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
            return Iter(types, filter).init(self);
        }

        pub fn getTables(self: *Self) []*Table {
            return self.tables.items;
        }
    };
}

pub const World = struct {
    allocator: std.mem.Allocator,

    entities: Entities,
    internal_entities: Entities,

    queries: Entity,
    world: Entity,

    pub fn init(allocator: std.mem.Allocator) !World {
        const List = std.ArrayListUnmanaged;

        var internal_entities = try Entities.init(allocator);
        var queries = try internal_entities.spawn();
        try internal_entities.set(List(*List(*Table)), queries, .{});

        return .{
            .allocator = allocator,
            .internal_entities = internal_entities,
            .entities = try Entities.init(allocator),
            .queries = queries,
            .world = try internal_entities.spawn(),
        };
    }

    pub fn deinit(self: *World) void {
        const List = std.ArrayListUnmanaged;

        var list = self.internal_entities.getPtr(List(*List(*Table)), self.queries) catch unreachable;

        for (list.items) |l| {
            l.deinit(self.allocator);
        }

        list.deinit(self.allocator);
        self.internal_entities.deinit();
        self.entities.deinit();
    }

    pub fn addSystem(self: *World, system: System) !void {
        const entity = try self.internal_entities.spawn();
        try self.internal_entities.set(System, entity, system);
    }

    pub fn spawn(self: *World) EntityBuilder {
        const entity = self.entities.spawn() catch unreachable;
        return EntityBuilder{
            .entities = &self.entities,
            .entity = entity,
        };
    }

    pub fn despawn(self: *World, entity: Entity) void {
        self.entities.despawn(entity) catch unreachable;
    }

    pub fn setComponent(self: *World, comptime T: type, entity: Entity, component: T) void {
        self.entities.set(T, entity, component) catch unreachable;
    }

    pub fn getComponent(self: *World, comptime T: type, entity: Entity) ?*const T {
        return self.entities.get(T, entity);
    }

    pub fn removeComponent(self: *World, comptime T: type, entity: Entity) void {
        self.entities.remove(T, entity) catch unreachable;
    }

    pub fn setResource(self: *World, comptime T: type, resource: T) void {
        self.internal_entities.set(T, self.world, resource) catch unreachable;
    }

    pub fn getResource(self: *World, comptime T: type) *T {
        return self.internal_entities.getPtr(T, self.world) catch unreachable;
    }

    pub fn removeResource(self: *World, comptime T: type) void {
        self.internal_entities.remove(T, self.world) catch unreachable;
    }

    pub fn isAlive(self: *World, entity: Entity) bool {
        return self.entities.isAlive(entity);
    }

    pub fn query(self: *World, comptime types: anytype) !*Query(types, .{}) {
        return try self.getQuery(types, &self.entities);
    }

    fn queryInternal(self: *World, comptime types: anytype) !*Query(types, .{}) {
        return try self.getQuery(types, &self.internal_entities);
    }

    fn getQuery(self: *World, comptime types: anytype, entts: *Entities) !*Query(types, .{}) {
        const Q = Query(types, .{});
        const List = std.ArrayListUnmanaged;

        var hasQuery = self.internal_entities.has(Q, self.queries);
        var ptr = try self.internal_entities.getPtr(Q, self.queries);

        if (!hasQuery) {
            ptr.* = try Q.init(self.allocator, entts);
            var list = try self.internal_entities.getPtr(List(*List(*Table)), self.queries);
            try list.append(self.allocator, &ptr.tables);
        }

        return ptr;
    }

    pub fn run(self: *World) !void {
        var q = try self.queryInternal(.{ .system = System });

        var it = q.iter();
        while (it.next()) |e| {
            try e.system.*(self);
        }
    }
};
