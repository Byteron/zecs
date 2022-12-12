const std = @import("std");

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

    hash: usize,

    id: usize,
    len: u32,
    capacity: u32,

    types: []ComponentType,
    block: [][]u8,

    pub fn init(allocator: std.mem.Allocator, id: usize, hash: usize, types: []ComponentType) !Table {
        var table = Table{
            .allocator = allocator,
            .hash = hash,
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

    pub fn new(self: *Table, entity: Entity) !u32 {
        var row = self.len;
        self.len += 1;

        try self.ensureCapacity();

        const entities = self.getStorage(Entity).?;
        entities[row] = entity;

        return row;
    }

    pub fn remove(self: *Table, row: u32) Entity {
        var entities = self.getStorage(Entity).?;
        self.len -= 1;
        var last = entities[self.len];

        for (self.types) |t, i| {
            const block = self.block[i];
            const dst_start = t.size * row;
            const dst = block[dst_start .. dst_start + t.size];
            const src_start = t.size * (self.len);
            const src = block[src_start .. src_start + t.size];
            std.mem.copy(u8, dst, src);
        }

        return last;
    }

    pub fn contains_type(self: *Table, component_type: ComponentType) bool {
        for (self.types) |t| {
            if (t.value == component_type.value) return true;
        }

        return false;
    }

    pub fn getRawStorage(self: *Table, component_type: ComponentType) ?[]u8 {
        for (self.types) |ct, i| {
            if (component_type.value == ct.value) {
                return self.block[i];
            }
        }

        return null;
    }

    pub fn getStorage(self: *Table, comptime T: type) ?[]T {
        const component_type = ComponentType.init(T);
        for (self.types) |ct, i| {
            if (component_type.value == ct.value) {
                const block = self.block[i];
                return @ptrCast([*]T, @alignCast(@alignOf(T), block))[0..self.len];
            }
        }

        return null;
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
    hashed_tables: std.AutoHashMapUnmanaged(usize, *Table) = .{},
    edges: std.ArrayListUnmanaged(std.AutoHashMapUnmanaged(usize, TableEdge)) = .{},

    entity_count: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) !Self {
        var entities = Self{
            .allocator = allocator,
            .entities = try allocator.alloc(EntityRecord, 256),
        };

        const types = try allocator.alloc(ComponentType, 1);
        const entity_type = ComponentType.init(Entity);
        types[0] = entity_type;

        _ = try entities.addTable(entity_type.value, types);

        return entities;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.entities);

        for (self.tables.items) |*table| {
            table.deinit();
        }

        for (self.edges.items) |*map| {
            map.deinit(self.allocator);
        }

        self.unused_ids.deinit(self.allocator);
        self.tables.deinit(self.allocator);
        self.edges.deinit(self.allocator);
        self.hashed_tables.deinit(self.allocator);
    }

    pub fn spawn(self: *Self) !Entity {
        var id = self.unused_ids.popOrNull() orelse blk: {
            self.entity_count += 1;
            self.entities[self.entity_count].gen = 0;
            break :blk self.entity_count;
        };

        var record = &self.entities[id];
        record.gen = -record.gen + 1;
        record.table = 0;

        const entity = Entity{
            .id = id,
            .gen = @intCast(u16, record.gen),
        };

        var table: *Table = &self.tables.items[0];
        const row = try table.new(entity);

        record.row = row;

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

    pub fn getComponent(self: *Self, comptime T: type, entity: Entity) ?*const T {
        var record = &self.entities[entity.id];
        const old_table = &self.tables.items[record.table];
        const old_row = record.row;

        const storage = old_table.getStorage(T) orelse return null;
        return &storage[old_row];
    }

    pub fn getComponentPtr(self: *Self, comptime T: type, entity: Entity) !*T {
        const component_type = ComponentType.init(T);

        var record = &self.entities[entity.id];
        const old_table = &self.tables.items[record.table];
        const old_row = record.row;

        if (old_table.getStorage(T)) |storage| {
            return &storage[old_row];
        }

        const old_map: *std.AutoHashMapUnmanaged(usize, TableEdge) = &self.edges.items[record.table];
        const old_result = try old_map.getOrPut(self.allocator, component_type.value);
        const old_edge: *TableEdge = old_result.value_ptr;

        if (!old_result.found_existing) {
            old_edge.* = .{};
        }

        var new_table: *Table = undefined;

        if (old_edge.add) |t| {
            new_table = t;
        } else {
            var hash = old_table.hash;
            hash ^= component_type.value;

            if (self.hashed_tables.contains(hash)) {
                new_table = self.hashed_tables.get(hash).?;
            } else {
                var types = try self.allocator.alloc(ComponentType, old_table.types.len + 1);
                std.mem.copy(ComponentType, types[0..], old_table.types);
                types[old_table.types.len] = component_type;
                std.sort.sort(ComponentType, types, {}, sortByTypeId);
                new_table = try self.addTable(hash, types);

                const new_map: *std.AutoHashMapUnmanaged(usize, TableEdge) = &self.edges.items[record.table];
                const new_result = try new_map.getOrPut(self.allocator, component_type.value);
                const new_edge: *TableEdge = new_result.value_ptr;

                if (!new_result.found_existing) {
                    new_edge.* = .{};
                }

                new_edge.remove = old_table;
            }
        }

        old_edge.add = new_table;

        var new_row = try new_table.new(entity);

        for (old_table.types) |t| {
            const old_storage = old_table.getRawStorage(t) orelse continue;
            const new_storage = new_table.getRawStorage(t) orelse continue;

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

        const storage = new_table.getStorage(T).?;
        return &storage[new_row];
    }

    pub fn modifyComponent(self: *Self, comptime T: type, entity: Entity, component: T) !void {
        const component_type = ComponentType.init(T);

        var record = &self.entities[entity.id];
        const table = &self.tables.items[record.table];
        const row = record.row;

        if (!table.contains_type(component_type)) {
            return error.Unknown;
        }

        var storage = try table.getStorage(T);
        storage[row] = component;
    }

    pub fn setComponent(self: *Self, comptime T: type, entity: Entity, component: T) !void {
        const component_ptr = try self.getComponentPtr(T, entity);
        component_ptr.* = component;
    }

    pub fn removeComponent(self: *Self, comptime T: type, entity: Entity) !void {
        const component_type = ComponentType.init(T);

        var record = &self.entities[entity.id];
        const old_table = &self.tables.items[record.table];
        const old_row = record.row;

        const old_map: *std.AutoHashMapUnmanaged(usize, TableEdge) = &self.edges.items[record.table];
        const old_result = try old_map.getOrPut(self.allocator, component_type.value);
        var old_edge: *TableEdge = old_result.value_ptr;

        if (!old_result.found_existing) {
            old_edge.* = .{};
        }

        var new_table: *Table = undefined;

        if (old_edge.remove) |t| {
            new_table = t;
        } else {
            var hash: usize = 0;
            for (old_table.types) |t| {
                if (t.value != component_type.value) hash ^= t.value;
            }

            if (self.hashed_tables.contains(hash)) {
                new_table = self.hashed_tables.get(hash).?;
            } else {
                var types = try self.allocator.alloc(ComponentType, old_table.types.len - 1);

                var index: u32 = 0;
                for (old_table.types) |t| {
                    if (t.value == component_type.value) continue;
                    types[index] = t;
                    index += 1;
                }

                new_table = try self.addTable(hash, types);

                const new_map: *std.AutoHashMapUnmanaged(usize, TableEdge) = &self.edges.items[record.table];
                const new_result = try new_map.getOrPut(self.allocator, component_type.value);
                const new_edge: *TableEdge = new_result.value_ptr;

                if (!new_result.found_existing) {
                    new_edge.* = .{};
                }

                new_edge.add = old_table;
            }
        }

        old_edge.remove = new_table;

        var new_row = try new_table.new(entity);

        for (new_table.types) |t| {
            const old_storage = old_table.getRawStorage(t) orelse continue;
            const new_storage = new_table.getRawStorage(t) orelse continue;

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
    }

    pub fn isAlive(self: *Self, entity: Entity) bool {
        const record = self.entities[entity.id];
        return record.gen == entity.gen;
    }

    fn addTable(self: *Self, hash: usize, types: []ComponentType) !*Table {
        const table = try Table.init(self.allocator, self.tables.items.len, hash, types);
        try self.tables.append(self.allocator, table);
        try self.hashed_tables.put(self.allocator, hash, &self.tables.items[table.id]);
        try self.edges.append(self.allocator, .{});
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

    const e1 = try entities.spawn();
    const e2 = try entities.spawn();

    try entities.setComponent(Position, e1, .{ .x = 5, .y = 5 });
    try entities.setComponent(Velocity, e1, .{ .x = 1 });
    try entities.setComponent(Health, e1, .{ .max = 10 });

    try entities.setComponent(Velocity, e2, .{ .x = 1 });
    try entities.setComponent(Health, e2, .{ .max = 10 });
    try entities.setComponent(Position, e2, .{ .x = 5, .y = 5 });

    try entities.despawn(e1);

    var e3 = try entities.spawn();

    try entities.setComponent(Health, e3, .{ .max = 10 });
    try entities.setComponent(Position, e3, .{ .x = 5, .y = 5 });
    try entities.setComponent(Velocity, e3, .{ .x = 1 });

    try std.testing.expect(entities.getComponent(Position, e3).?.x == 5);

    const pos = try entities.getComponentPtr(Position, e3);
    pos.y = 10;

    try std.testing.expect(entities.getComponent(Position, e3).?.y == 10);

    try entities.removeComponent(Health, e3);
    try entities.removeComponent(Position, e3);
    try entities.removeComponent(Velocity, e3);
    try entities.removeComponent(Velocity, e2);

    try std.testing.expect(entities.getComponent(Position, e3) == null);

    try entities.setComponent(Position, e3, .{});
}
