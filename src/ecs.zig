const std = @import("std");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const alloc = gpa.allocator();

pub const World = struct {
    entity_count: usize,
    pools: std.AutoHashMap(usize, *c_void),

    pub fn init() World {
        return World{
            .entity_count = 0,
            .pools = std.AutoHashMap(usize, *c_void).init(alloc),
        };
    }

    pub fn deinit(self: *World) void {
        _ = self;
        // TODO: deinit pools
    }

    pub fn spawn(self: *World) usize {
        var entity = self.entity_count;
        self.entity_count += 1;
        return entity;
    }

    pub fn add(self: *World, entity: usize, component: anytype) !void {
        const T = @TypeOf(component);
        const type_id = typeId(T);

        var pool: *Pool(T) = undefined;
        if (self.pools.contains(type_id)) {
            var pool_ptr = self.*.pools.get(type_id).?;
            pool = ptrToStruct(Pool(T), pool_ptr);
        } else {
            pool = try alloc.create(Pool(T));
            pool.* = Pool(T).init(alloc);
            var pool_ptr = structToPtr(pool);
            try self.pools.put(type_id, pool_ptr);
        }

        try pool.add(entity, component);
    }

    pub fn get(self: *World, comptime T: type, entity: usize) !*T {
        const type_id = typeId(T);
        var pool_ptr = self.pools.get(type_id).?;
        var pool = ptrToStruct(Pool(T), pool_ptr);
        return pool.get(entity);
    }

    pub fn remove(self: *World, comptime T: type, entity: usize) void {
        const type_id = typeId(T);
        var pool_ptr = self.pools.get(type_id).?;
        var pool = ptrToStruct(Pool(T), pool_ptr);
        pool.remove(entity);
    }

    pub fn has(self: *World, comptime T: type, entity: usize) bool {
        const type_id = typeId(T);
        var pool_ptr = self.pools.get(type_id).?;
        var pool = ptrToStruct(Pool(T), pool_ptr);
        return pool.has(entity);
    }

    pub fn query(self: *World, arche_type: anytype) ![]usize {
        const ArcheType = @TypeOf(arche_type);

        if (@typeInfo(ArcheType) != .Struct) {
            @compileError("Expected tuple or struct argument, found " ++ @typeName(ArcheType));
        }

        var list = std.ArrayList(usize).init(alloc);

        var index: usize = 0;
        while (index < self.entity_count) : (index += 1) {
            var has_components = true;

            inline for (arche_type) |T| {
                if (!self.has(T, index)) {
                    has_components = false;
                }
            }

            if (has_components) {
                try list.append(index);
            }
        }

        return list.items;
    }
};

pub fn Pool(comptime T: type) type {
    return struct {
        const Self = @This();

        indices: std.AutoHashMap(usize, usize),
        components: std.ArrayList(T),

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .indices = std.AutoHashMap(usize, usize).init(allocator),
                .components = std.ArrayList(T).init(allocator),
            };
        }

        pub fn add(self: *Pool(T), entity: usize, component: T) !void {
            if (self.indices.contains(entity)) {
                self.components.items[self.indices.get(entity).?] = component;
            }
            else
            {
                try self.components.append(component);
                try self.indices.put(entity, self.components.items.len - 1);
            }
            
        }

        pub fn get(self: *Pool(T), entity: usize) !*T {
            return &self.components.items[self.indices.get(entity).?];
        }

        pub fn remove(self: *Pool(T), entity: usize) void {
            _ = self.indices.remove(entity);
        }

        pub fn has(self: Pool(T), entity: usize) bool {
            return self.indices.contains(entity);
        }
    };
}

fn structToPtr(s: anytype) *c_void {
    return @ptrCast(*c_void, s);
}

fn ptrToStruct(comptime T: type, ptr: *c_void) *T {
    return @ptrCast(*T, @alignCast(@alignOf(T), ptr));
}

fn TypeId(comptime T: type) type {
    _ = T;
    return struct {
        pub var uniq: u8 = 0;
    };
}

fn typeId(comptime T: type) usize {
    return @ptrToInt(&TypeId(T).uniq);
}
