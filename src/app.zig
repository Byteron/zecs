const Module = struct {
    const Self = @This();
    
    pub fn init() Self {
        return Self{};
    }
    
    pub fn register_components(self: *Self, comptime components: anytype) *Self {
        _ = components;
        return self;
    }
    
    pub fn add_system(self: *Self, comptime message: anytype, comptime system: anytype) *Self {
        _ = message;
        _ = system;
        return self;
    }
};

const App = struct {
    const Self = @This();
    
    pub fn init() Self {
        return Self{};
    }
    
    pub fn register_components(self: *Self, comptime components: anytype) *Self {
        _ = components;
        return self;
    }
    
    pub fn add_module(self: *Self, comptime module: anytype) *Self {
        _ = module;
        return self;
    }
    
    pub fn add_system(self: *Self, comptime message: anytype, comptime system: anytype) *Self {
        _ = message;
        _ = system;
        return self;
    }
    
    pub fn run() void { 
    }
};

test {
    const Position = struct {};
    const Velocity = struct {};
    const Health = struct {};
    
    const PhysicsComponents = .{
        .position = Position,
        .velocity = Velocity,
    };
    
    const AppComponents = .{
        .health = Health,
    };
    
    const Message = enum {
        tick,
    };
    
    var module = Module.init()
        .register_components(PhysicsComponents)
        .add_system(.tick, module_system);
    
    App.init()
        .register_components(AppComponents)
        .add_system(.tick, ).run(PhysicsComponents)
        .run();
    
    _ = module;
    _ = Message;
}

fn module_system() void {
    
}

fn app_system() void {
    
}