const std = @import("std");

pub const Error = error{
    Unknown,
};

pub const Entity = struct {
    id: u32,
    gen: u16,
};

const EntityRecord = struct {
    table: usize,
    row: u32,
    gen: i16,
};

const ComponentType = struct {
    value: usize,
    size: u32,

    pub fn init(comptime T: type) ComponentType {
        return ComponentType{
            .value = getTypeValue(T),
            .size = @sizeOf(T),
        };
    }
};

fn getTypeValue(comptime T: type) usize {
    _ = T;
    return @ptrToInt(&struct {
        var x: u8 = 0;
    }.x);
}

fn sortByTypeId(context: void, lhs: ComponentType, rhs: ComponentType) bool {
    _ = context;
    return lhs.value < rhs.value;
}

const TableEdge = struct {
    add: ?*Table = null,
    remove: ?*Table = null,
};

pub const Table = struct {
    allocator: std.mem.Allocator,

    id: usize,
    len: u32,
    capacity: u32,

    types: []ComponentType,
    block: [][]u8,

    pub fn init(allocator: std.mem.Allocator, id: usize, types: []ComponentType) !Table {
        var table = Table{
            .allocator = allocator,
            .id = id,
            .len = 0,
            .capacity = 0,
            .types = types,
            .block = try allocator.alloc([]u8, types.len),
        };

        try table.setCapacity(1);

        return table;
    }

    pub fn deinit(self: *Table) void {
        self.allocator.free(self.types);

        for (self.block) |block| {
            self.allocator.free(block);
        }

        self.allocator.free(self.block);
    }

    pub fn new(self: *Table) !u32 {
        var row = self.len;
        self.len += 1;

        try self.ensureCapacity();

        std.debug.print("added new row to table {}\n", .{self.id});

        return row;
    }

    pub fn remove(self: *Table, row: u32) Entity {
        var entities = self.getStorage(Entity) catch unreachable;
        self.len -= 1;
        var current = entities[row];
        var last = entities[self.len];

        for (self.types) |t, i| {
            const block = self.block[i];
            const dst_start = t.size * row;
            const dst = block[dst_start .. dst_start + t.size];
            const src_start = t.size * (self.len);
            const src = block[src_start .. src_start + t.size];
            std.mem.copy(u8, dst, src);
        }

        std.debug.print("removed entity {} to table {}\n", .{ current.id, self.id });
        return last;
    }

    pub fn contains_type(self: *Table, component_type: ComponentType) bool {
        for (self.types) |t| {
            if (t.value == component_type.value) return true;
        }

        return false;
    }

    pub fn getRawStorage(self: *Table, component_type: ComponentType) ![]u8 {
        for (self.types) |ct, i| {
            if (component_type.value == ct.value) {
                return self.block[i];
            }
        }

        return error.Unknown;
    }

    pub fn getStorage(self: *Table, comptime T: type) ![]T {
        const component_type = ComponentType.init(T);
        for (self.types) |ct, i| {
            if (component_type.value == ct.value) {
                const block = self.block[i];
                return @ptrCast([*]T, @alignCast(@alignOf(T), block))[0..self.len];
            }
        }

        return error.Unknown;
    }

    pub fn ensureCapacity(self: *Table) !void {
        if (self.len == self.capacity) {
            try self.setCapacity(self.len + 1);
        }
    }

    pub fn setCapacity(self: *Table, capacity: u32) !void {
        for (self.types) |component_type, i| {
            const new_block = try self.allocator.alloc(u8, capacity * component_type.size);

            if (self.capacity > 0) {
                const old_block = self.block[i];
                std.mem.copy(u8, new_block[0..], old_block);
                self.allocator.free(old_block);
            }

            self.block[i] = new_block;
        }

        self.capacity = capacity;
    }
};

pub const Entities = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    entities: []EntityRecord,
    unused_ids: std.ArrayListUnmanaged(u32) = .{},

    tables: std.ArrayListUnmanaged(Table) = .{},
    edges: std.ArrayListUnmanaged(std.AutoHashMapUnmanaged(usize, TableEdge)) = .{},

    entity_count: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) !Self {
        var entities = Self{
            .allocator = allocator,
            .entities = try allocator.alloc(EntityRecord, 256),
        };

        const types = try allocator.alloc(ComponentType, 1);
        types[0] = ComponentType.init(Entity);

        _ = try entities.addTable(types);

        return entities;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.entities);

        for (self.tables.items) |*table| {
            table.deinit();
        }

        for (self.edges.items) |*map, i| {
            map.deinit(self.allocator);
            std.debug.print("deinit hash map: {d}\n", .{i});
        }

        self.unused_ids.deinit(self.allocator);
        self.tables.deinit(self.allocator);
        self.edges.deinit(self.allocator);
    }

    pub fn spawn(self: *Self) !Entity {
        var id = self.unused_ids.popOrNull() orelse blk: {
            self.entity_count += 1;
            self.entities[self.entity_count].gen = 0;
            break :blk self.entity_count;
        };

        var table: *Table = &self.tables.items[0];
        const row = try table.new();

        var record = &self.entities[id];
        record.table = 0;
        record.gen = -record.gen + 1;
        record.row = row;

        const entity = Entity{
            .id = id,
            .gen = @intCast(u16, record.gen),
        };

        const entities = try table.getStorage(Entity);
        entities[row] = entity;

        return entity;
    }

    pub fn despawn(self: *Self, entity: Entity) !void {
        var record = &self.entities[entity.id];
        var table = self.tables.items[record.table];

        const last_entity = table.remove(record.row);

        var last_record = &self.entities[last_entity.id];
        last_record.row = record.row;

        record.gen = -record.gen;

        try self.unused_ids.append(self.allocator, entity.id);
    }

    pub fn addComponent(self: *Self, comptime T: type, entity: Entity, component: T) !void {
        const component_type = ComponentType.init(T);

        var record = &self.entities[entity.id];
        const old_table = &self.tables.items[record.table];
        const old_row = record.row;

        if (old_table.contains_type(component_type)) {
            return error.Unknown;
        }

        const map: *std.AutoHashMapUnmanaged(usize, TableEdge) = &self.edges.items[record.table];
        const result = try map.getOrPut(self.allocator, component_type.value);
        var edge: *TableEdge = result.value_ptr;

        if (!result.found_existing) {
            edge.* = .{};
            std.debug.print("added table edge\n", .{});
        }

        var new_table: *Table = undefined;

        if (edge.add) |t| {
            new_table = t;
        } else {
            var types = try self.allocator.alloc(ComponentType, old_table.types.len + 1);
            std.mem.copy(ComponentType, types[0..], old_table.types);
            types[old_table.types.len] = component_type;
            std.sort.sort(ComponentType, types, {}, sortByTypeId);
            new_table = try self.addTable(types);
        }

        edge.add = new_table;

        var new_row = try new_table.new();

        // copy components

        for (old_table.types) |t| {
            const old_storage = try old_table.getRawStorage(t);
            const new_storage = try new_table.getRawStorage(t);

            const dst_start = t.size * new_row;
            const dst = new_storage[dst_start .. dst_start + t.size];
            const src_start = t.size * old_row;
            const src = old_storage[src_start .. src_start + t.size];

            std.mem.copy(u8, dst, src);
        }

        var last_entity = old_table.remove(old_row);
        var last_record = &self.entities[last_entity.id];
        last_record.row = old_row;

        record.table = new_table.id;
        record.row = new_row;
        // set component

        _ = component;
    }

    pub fn isAlive(self: *Self, entity: Entity) bool {
        const record = self.entities[entity.id];
        return record.gen == entity.gen;
    }

    fn addTable(self: *Self, types: []ComponentType) !*Table {
        var table = try Table.init(self.allocator, self.tables.items.len, types);
        try self.tables.append(self.allocator, table);
        try self.edges.append(self.allocator, .{});
        std.debug.print("new table and edge map: {d}\n", .{table.id});
        return &self.tables.items[self.tables.items.len - 1];
    }
};

test "spawn_entities" {
    var entities = try Entities.init(std.testing.allocator);
    defer entities.deinit();

    const e1 = try entities.spawn();
    const e2 = try entities.spawn();
    const e3 = try entities.spawn();

    try std.testing.expect(e1.id == 1);
    try std.testing.expect(e2.id == 2);
    try std.testing.expect(e3.id == 3);

    try entities.despawn(e1);
    try entities.despawn(e2);

    try std.testing.expect(!entities.isAlive(e1));
    try std.testing.expect(!entities.isAlive(e2));

    const e4 = try entities.spawn();
    const e5 = try entities.spawn();

    try std.testing.expect(e4.id == 2);
    try std.testing.expect(e5.id == 1);

    try std.testing.expect(entities.isAlive(e4));
    try std.testing.expect(entities.isAlive(e5));

    try std.testing.expect(!entities.isAlive(e1));
    try std.testing.expect(!entities.isAlive(e2));
}

test "components" {
    const Position = struct {
        x: f32 = 0,
        y: f32 = 0,
    };

    const Velocity = struct {
        x: f32 = 0,
        y: f32 = 0,
    };

    const Health = struct {
        max: u32,
        current: u32 = 0,
    };

    var entities = try Entities.init(std.testing.allocator);
    defer entities.deinit();

    const e = try entities.spawn();

    try entities.addComponent(Position, e, .{ .x = 5, .y = 5 });
    try entities.addComponent(Velocity, e, .{ .x = 1 });
    try entities.addComponent(Health, e, .{ .max = 10 });
}
