const std = @import("std");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const alloc = gpa.allocator();

pub const World = struct {
    pools: std.AutoHashMap(usize, *c_void),

    pub fn init() World {
        return World{
            .pools = std.AutoHashMap(usize, *c_void).init(alloc),
        };
    }

    pub fn add(self: *World, component: anytype) !void {
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

        try pool.add(component);
    }

    pub fn get(self: *World, comptime T: type, index: usize) !T {
        const type_id = typeId(T);

        var pool_ptr = self.pools.get(type_id).?;
        var pool = ptrToStruct(Pool(T), pool_ptr);
        return pool.get(index);
    }
};

pub fn Pool(comptime T: type) type {
    return struct {
        const Self = @This();

        components: std.ArrayList(T),

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .components = std.ArrayList(T).init(allocator),
            };
        }

        pub fn add(self: *Pool(T), component: T) !void {
            try self.components.append(component);
        }

        pub fn get(self: *Pool(T), index: usize) !T {
            return self.components.items[index];
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
