const std = @import("std");

pub const Error = error{
    Unknown,
};

pub const Entity = struct {
    id: u32,
    gen: u16,
};

const EntityRecord = struct {
    table: u32,
    row: u32,
    gen: i32,
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
    return @enumToInt(lhs.value) < @enumToInt(rhs.value);
}

pub const Table = struct {
    allocator: std.mem.Allocator,

    len: u32,
    capacity: u32,

    types: []ComponentType,
    block: [][]u8,

    pub fn init(allocator: std.mem.Allocator, types: []ComponentType) !Table {
        var table = Table{
            .allocator = allocator,
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

        return row;
    }

    pub fn remove(self: *Table, row: u32) Entity {
        var entities = self.getStorage(Entity) catch unreachable;
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

    pub fn getStorage(self: *Table, comptime T: type) ![]T {
        const type_value = getTypeValue(T);
        for (self.types) |component_type, i| {
            if (component_type.value == type_value) {
                const block = self.block[i];
                return @ptrCast([*]T, @alignCast(@alignOf(T), block))[0..self.len];
            }
        }

        return error.Unknown;
    }

    pub fn getStorageByIndex(self: *Table, comptime T: type, index: usize) []T {
        const block = self.block[index];
        return @ptrCast([*]T, @alignCast(@alignOf(T), block))[0..self.len];
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

    entity_count: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) !Self {
        var entities = Self{
            .allocator = allocator,
            .entities = try allocator.alloc(EntityRecord, 256),
        };

        const types = try allocator.alloc(ComponentType, 1);
        types[0] = ComponentType.init(Entity);

        const table = try Table.init(allocator, types);

        try entities.tables.append(allocator, table);

        return entities;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.entities);

        for (self.tables.items) |*table| {
            table.deinit();
        }
        self.unused_ids.deinit(self.allocator);
        self.tables.deinit(self.allocator);
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

        const entities = table.getStorageByIndex(Entity, 0);
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

    pub fn isAlive(self: *Self, entity: Entity) bool {
        const record = self.entities[entity.id];
        return record.gen == entity.gen;
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
