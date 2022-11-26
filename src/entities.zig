const std = @import("std");

pub const Entity = u64;

const EntityRecord = struct {
    table: u16,
    row: u32,
};

const TypeId = enum(usize) { _ };

// typeId implementation by Felix "xq" Queißner
fn typeId(comptime T: type) TypeId {
    _ = T;
    return @intToEnum(TypeId, @ptrToInt(&struct {
        var x: u8 = 0;
    }.x));
}

const ComponentType = struct {
    typeId: TypeId,
    size: u32,
};

const Archetype = struct {
    const Self = @This();

    hash: u64,
    types: []ComponentType,

    pub fn init(allocator: std.mem.Allocator, comptime component_types: anytype) !Self {
        const ComponentTypes = @TypeOf(component_types);
        const typeInfo = @typeInfo(ComponentTypes);

        if (typeInfo != .Struct) {
            @compileError("Expected tuple or struct argument, found " + @typeName(ComponentTypes));
        }

        const len = typeInfo.Struct.fields.len;
        var componentTypes = try allocator.alloc(ComponentType, len);

        var hash: u64 = 0;
        comptime var index = 0;
        inline for (component_types) |T| {
            componentTypes[index] = ComponentType{
                .typeId = typeId(T),
                .size = @sizeOf(T),
            };

            hash ^= @enumToInt(typeId(T));
            index += 1;
        }

        return Self{
            .types = componentTypes,
            .hash = hash,
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.types);
    }
};

// pub fn Archetype(comptime component_types: anytype) type {
//     return struct {
//         const Self = @This();

//         allocator: std.mem.Allocator,

//         hash: u64,
//         types: []ComponentType,

//         pub fn init(allocator: std.mem.Allocator) !Self {
//             const ComponentTypes = @TypeOf(component_types);
//             const typeInfo = @typeInfo(ComponentTypes);

//             if (typeInfo != .Struct) {
//                 @compileError("Expected tuple or struct argument, found " + @typeName(ComponentTypes));
//             }

//             const len = typeInfo.Struct.fields.len;
//             var componentTypes = try allocator.alloc(ComponentType, len);

//             comptime var index = 0;
//             inline for (component_types) |T| {
//                 componentTypes[index] = ComponentType{
//                     .typeId = typeId(T),
//                     .size = @sizeOf(T),
//                 };
//                 index += 1;
//             }

//             return Self{
//                 .allocator = allocator,
//                 .hash = 0,
//                 .types = componentTypes,
//             };
//         }

//         pub fn deinit(self: *Self) void {
//             self.allocator.free(self.types);
//         }
//     };
// }

pub const Table = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    len: u32,
    capacity: u32,

    archetype: Archetype,

    block: []u8,

    pub fn init(allocator: std.mem.Allocator, comptime component_types: anytype) !Self {
        var table =  Self{
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

    fn ensureCapacity(self: *Self) !void {
        if (self.len >= self.capacity) {
            try self.setCapacity(self.capacity << 1);
        }
    }
    
    fn setCapacity(self: *Self, new_capacity: u32) !void {
        const old_capacity = self.capacity;

        var archetype_size: usize = 0;

        for (self.archetype.types) |*componentType| {
            archetype_size += componentType.size;
        }

        const new_block_size = archetype_size * new_capacity;

        const old_block = self.block;
        const new_block = try self.allocator.alloc(u8, new_block_size);

        var offset: usize = 0;
        for (self.archetype.types) |*componentType| {
            const old_component_block_size = componentType.size * old_capacity;
            const new_component_block_size = componentType.size * new_capacity;

            if (self.capacity > 0) {
                const slice = old_block[offset .. offset + old_component_block_size];
                std.mem.copy(u8, new_block[offset..], slice);
            }

            offset += new_component_block_size;
        }

        if (self.capacity > 0) {
            self.allocator.free(old_block);
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
            .allocator = allocator ,
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

        const record = EntityRecord{
            .table = 0,
            .row = row,
        };

        try self.entities.put(self.allocator, id, record);

        return id;
    }
};

fn structToPtr(s: anytype) *void {
    return @ptrCast(*void, s);
}

fn ptrToStruct(comptime T: type, ptr: *void) *T {
    return @ptrCast(*T, @alignCast(@alignOf(T), ptr));
}

test "type_id_creation" {
    const Position = struct {};
    const Velocity = struct {};

    const posType = typeId(Position);
    const velType = typeId(Velocity);
    const posType2 = typeId(Position);
    const velType2 = typeId(Velocity);

    try std.testing.expect(posType == posType2);
    try std.testing.expect(velType == velType2);

    try std.testing.expect(posType != velType);

    std.debug.print("{}: {}", .{ Position, typeId(Position) });
    std.debug.print("{}: {}", .{ Velocity, typeId(Velocity) });
}

test "archetype_creation" {
    const alloc = std.testing.allocator;

    const Position = struct {};
    const Velocity = struct {};

    var archetype = try Archetype.init(alloc, .{ Position, Velocity });
    defer archetype.deinit(alloc);

    const type1: ComponentType = archetype.types[0];
    const type2: ComponentType = archetype.types[1];

    try std.testing.expect(type1.typeId == typeId(Position));
    try std.testing.expect(type2.typeId == typeId(Velocity));
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

test "set_components" {
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