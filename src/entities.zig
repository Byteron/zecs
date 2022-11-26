const std = @import("std");

pub const Entity = u64;

const EntityRecord = struct {
    table: u64,
    row: u32,
};

const TypeId = enum(usize) { _ };

// typeId implementation by Felix "xq" Queißner
fn getTypeId(comptime T: type) TypeId {
    _ = T;
    return @intToEnum(TypeId, @ptrToInt(&struct {
        var x: u8 = 0;
    }.x));
}

const ComponentType = struct {
    type_id: TypeId,
    offset: usize,
    size: u32,
};

fn sort_by_type_id(context: void, lhs: ComponentType, rhs: ComponentType) bool {
    _ = context;
    return @enumToInt(lhs.type_id) < @enumToInt(rhs.type_id);
}

const Archetype = struct {
    const Self = @This();

    hash: u64,
    types: []ComponentType,

    pub fn init(allocator: std.mem.Allocator, comptime component_types: anytype) !Self {
        const ComponentTypes = @TypeOf(component_types);
        const type_info = @typeInfo(ComponentTypes);

        if (type_info != .Struct) {
            @compileError("Expected tuple or struct argument, found " + @typeName(ComponentTypes));
        }

        const len = typeInfo.Struct.fields.len;
        var types = try allocator.alloc(ComponentType, len);

        comptime var index = 0;
        inline for (component_types) |T| {
            const type_id = getTypeId(T);
            types[index] = ComponentType{
                .type_id = type_id,
                .size = @sizeOf(T),
                .offset = undefined,
            };

            index += 1;
        }

        std.sort.sort(ComponentType, types, {}, sort_by_type_id);

        var hash: u64 = 0;
        inline for (types) |component_type| {
            hash ^= @enumToInt(component_type.type_id);
        }

        return Self{
            .hash = hash,
            .types = types,
        };
    }

    pub fn with(self: *Self, comptime T: type) Self {
        const type_info = @typeInfo(T);

        const len = self.types.len + 1;
        var types = try allocator.alloc(ComponentType, len);

        comptime var index = 0;
        inline for (self.types) |component_type| {
            const type_id = getTypeId(T);
            types[index] = component_type;
            index += 1;
        }

        types[index] = ComponentType{
            .type_id = getTypeId(T),
            .size = @sizeOf(T),
            .offset = undefined,
        };

        std.sort.sort(ComponentType, types, {}, sort_by_type_id);

        var hash: u64 = 0;
        inline for (types) |component_type| {
            hash ^= @enumToInt(component_type.type_id);
        }

        return Archetype{
            .hash = hash,
            .types = types,
        };
    }

    pub fn without(self: *Self, comptime T: type) Self {
        const type_info = @typeInfo(T);

        const len = self.types.len - 1;
        var types = try allocator.alloc(ComponentType, len);

        comptime var index = 0;
        inline for (self.types) |component_type| {
            const type_id = getTypeId(T);

            if (type_id == component_type.type_id) {
                continue;
            }

            types[index] = component_type;
            index += 1;
        }

        var hash: u64 = 0;
        inline for (types) |component_type| {
            hash ^= @enumToInt(component_type.type_id);
        }

        return Archetype{
            .hash = hash,
            .types = types,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.types);
    }
};

pub const Table = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    len: u32,
    capacity: u32,

    archetype: Archetype,

    block: []u8,

    pub fn init(allocator: std.mem.Allocator, comptime component_types: anytype) !Self {
        var table = Self{
            .allocator = allocator,
            .len = 0,
            .capacity = 0,
            .archetype = try Archetype.init(allocator, component_types),
            .block = undefined,
        };

        try table.setCapacity(1);

        return table;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.block);
        self.archetype.deinit(self.allocator);
    }

    pub fn new(self: *Self) !u32 {
        var row = self.len;
        self.len += 1;

        try self.ensureCapacity();

        return row;
    }

    pub fn get(self: *Self, comptime T: type, row: u32) ?T {
        for (self.archetype.types) |componentType| {
            if (componentType.typeId == getTypeId(T)) {
                const columnValues = @ptrCast([*]T, @alignCast(@alignOf(T), &self.block[componentType.offset]));
                return columnValues[row];
            }
        }

        return null;
    }

    pub fn set(self: *Self, comptime T: type, row: u32, component: T) !void {
        for (self.archetype.types) |componentType| {
            if (componentType.typeId == getTypeId(T)) {
                const columnValues = @ptrCast([*]T, @alignCast(@alignOf(T), &self.block[componentType.offset]));
                columnValues[row] = component;
                return;
            }
        }

        @panic("component could not be set");
    }

    fn ensureCapacity(self: *Self) !void {
        if (self.len >= self.capacity) {
            try self.setCapacity(self.capacity << 1);
        }
    }

    fn setCapacity(self: *Self, new_capacity: u32) !void {
        var archetype_size: usize = 0;
        for (self.archetype.types) |*componentType| {
            archetype_size += componentType.size;
        }

        const new_block = try self.allocator.alloc(u8, archetype_size * new_capacity);

        var offset: usize = 0;
        for (self.archetype.types) |*componentType| {
            if (self.capacity > 0) {
                const offset_end = self.capacity * componentType.size + componentType.offset;
                const slice = self.block[componentType.offset..offset_end];
                std.mem.copy(u8, new_block[offset..], slice);
            }

            componentType.offset = offset;
            offset += componentType.size * new_capacity;
        }

        if (self.capacity > 0) {
            self.allocator.free(self.block);
        }

        self.block = new_block;
        self.capacity = new_capacity;
    }
};

pub const Entities = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    entity_count: u32 = 0,

    entities: std.AutoArrayHashMapUnmanaged(Entity, EntityRecord) = .{},
    tables: std.AutoArrayHashMapUnmanaged(u64, Table) = .{},

    entity_archetype: Archetype,

    pub fn init(allocator: std.mem.Allocator) !Self {
        const entity_table = try Table.init(allocator, .{Entity});

        var entities = Self{
            .allocator = allocator,
            .entity_archetype = entity_table.archetype,
        };

        entities.entity_archetype = entity_table.archetype;

        try entities.tables.put(allocator, entity_table.archetype.hash, entity_table);

        return entities;
    }

    pub fn deinit(self: *Self) void {
        self.entities.deinit(self.allocator);

        var iter = self.tables.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }

        self.tables.deinit(self.allocator);
    }

    pub fn spawn(self: *Self) !Entity {
        self.entity_count += 1;
        const id = self.entity_count;

        var entity_table = self.tables.getPtr(self.entity_archetype.hash).?;
        const row = try entity_table.new();

        try entity_table.set(Entity, row, id);

        const record = EntityRecord{
            .table = self.entity_archetype.hash,
            .row = row,
        };

        try self.entities.put(self.allocator, id, record);

        return id;
    }

    pub fn addComponent(self: *Self, comptime T: type, entity: Entity, component: anytype) !void {
        const record: *EntityRecord = self.entities.getPtr(entity).?;
        const table: *Table = self.tables.getPtr(record.table).?;
        const new_archetype = table.archetype.with(T);

        // TODO: make the table move

        if (self.tables.getPtr(new_archetype.hash)) |new_table| {
            const new_row = new_table.new();

            record.row = new_row;
        } else {

        }
    }

    pub fn removeComponent(comptime T: type, entity: Entity) !void {
        // TODO: implement removeComponent
    }

    pub fn getComponent(self: *Self, comptime T: type, entity: Entity) T {
        const record = self.entities.getPtr(entity).?;
        const table = self.tables.getPtr(record.table).?;
        return table.get(T, record.row).?;
    }

    pub fn setComponent(self: *Self, comptime T: type, entity: Entity, component: T) !void {
        const record = self.entities.getPtr(entity).?;
        const table = self.tables.getPtr(record.table).?;
        return table.set(T, record.row, component);
    }
};

test "type_id_creation" {
    const Position = struct {};
    const Velocity = struct {};

    const posType = getTypeId(Position);
    const velType = getTypeId(Velocity);
    const posType2 = getTypeId(Position);
    const velType2 = getTypeId(Velocity);

    try std.testing.expect(posType == posType2);
    try std.testing.expect(velType == velType2);

    try std.testing.expect(posType != velType);

    std.debug.print("{}: {}", .{ Position, getTypeId(Position) });
    std.debug.print("{}: {}", .{ Velocity, getTypeId(Velocity) });
}

test "archetype_creation" {
    const alloc = std.testing.allocator;

    const Position = struct {};
    const Velocity = struct {};

    var archetype = try Archetype.init(alloc, .{ Position, Velocity });
    defer archetype.deinit(alloc);

    const type1: ComponentType = archetype.types[0];
    const type2: ComponentType = archetype.types[1];

    try std.testing.expect(type1.typeId == getTypeId(Position));
    try std.testing.expect(type2.typeId == getTypeId(Velocity));
    try std.testing.expect(type1.size == @sizeOf(Position));
    try std.testing.expect(type2.size == @sizeOf(Velocity));
}

test "table_creation" {
    const alloc = std.testing.allocator;

    const Position = struct {};
    const Velocity = struct {};

    var table = try Table.init(alloc, .{ Position, Velocity });
    defer table.deinit();
}

test "entities_creation" {
    const alloc = std.testing.allocator;
    var entities = try Entities.init(alloc);
    defer entities.deinit();
}

test "spawn_entities" {
    const alloc = std.testing.allocator;
    var entities = try Entities.init(alloc);
    defer entities.deinit();

    const entity1 = try entities.spawn();
    const entity2 = try entities.spawn();
    const entity3 = try entities.spawn();
    const entity4 = try entities.spawn();
    const entity5 = try entities.spawn();

    try std.testing.expect(entity1 == 1);
    try std.testing.expect(entity2 == 2);
    try std.testing.expect(entity3 == 3);
    try std.testing.expect(entity4 == 4);
    try std.testing.expect(entity5 == 5);
}

test "get_set_component" {
    const alloc = std.testing.allocator;
    var entities = try Entities.init(alloc);
    defer entities.deinit();

    const entity = try entities.spawn();
    var entity_component = entities.getComponent(Entity, entity);

    try std.testing.expect(entity == entity_component);

    try entities.setComponent(Entity, entity, 5);

    entity_component = entities.getComponent(Entity, entity);

    try std.testing.expect(entity_component == 5);
}

test "add_remove_component" {
    const alloc = std.testing.allocator;

    const Position = struct {
        x: f32,
        y: f32,
    };

    const Velocity = struct {
        x: f32,
        y: f32,
    };

    var entities = try Entities.init(alloc);
    defer entities.deinit();

    const entity = try entities.spawn();

    entities.addComponent(Position, entity, .{ .x = 5, .y = 5 });
    entities.addComponent(Velocity, entity, .{ .x = 10, .y = 10 });

    try std.testing.expect(entity == entity_component);

    try entities.setComponent(Entity, entity, 5);

    entity_component = entities.get(Entity, entity);

    try std.testing.expect(entity_component == 5);
}
