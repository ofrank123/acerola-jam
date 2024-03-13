const std = @import("std");
const dlog = std.log.debug;
const assert = std.debug.assert;

const bind = @import("./bindings.zig");
const entities = @import("./entities.zig");
const collision = @import("./collision.zig");
const render = @import("./render.zig");
const hud = @import("./hud.zig");

const Entity = entities.Entity;
const EntityTag = entities.EntityTag;
const EntityID = entities.EntityID;
const ColliderList = collision.ColliderList;
const RenderQueue = render.RenderQueue;

//------------------------------
//~ ojf: constants

pub const max_entities = 512;
pub const mouse_clicked_frames = 5;
pub const mouse_moving_frames = 5;
pub const mouse_range = 150;

pub const dropped_expiration = 5;
pub const max_ingredients = 8;
pub const ingredient_size = 48;

pub const long_table_size = Vec2{ 120, 320 };
pub const long_table_collider_size = Vec2{ 100, 300 };
pub const round_table_size = 170;
pub const round_table_collider_size = 150;

pub const max_stoves = 5;
pub const stove_size = 64;
pub const stove_ring_size = 80;
pub const stove_ingredient_radius = 16;
pub const stove_ingredient_size = 20;
pub const stove_fire_rot_time = 0.25;

pub const cooking_time = 5;
pub const ingredient_spin_speed = 0.5;
pub const dish_size = 42;

pub const customer_size = 80;
pub const customer_spawn_time = 10;
pub const customer_wait_time = 10;
pub const customer_eat_time = 15;
pub const customer_dialog_size = Vec2{ 80, 64 };
pub const customer_dialog_offset = 60;
pub const customer_fire_time = 3;
pub const customer_safe_radius = 100;

pub const seat_size = 32;
pub const seat_offset_x = 20;
pub const seat_offset_y = 30;
pub const seat_dish_target_offset = 44;
pub const seat_dish_target_size = 80;
pub const seat_utensils_sprite_size = 60;

pub const projectile_size = 32;
pub const projectile_spin_speed = 20;
pub const projectile_collider_size = 12;
pub const projectile_speed = 200;

pub const cursor_size = 64;

pub const start_button_pos = Vec2{ 840, 180 };
pub const start_button_size = Vec2{ 361, 82 };

//------------------------------
//~ ojf: logging

pub fn wasmLogFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    //- ojf: we don't have access to any outside state, so just use
    // a flat buffer to format
    var buf = [_]u8{0} ** 2046;
    var log_fb = std.heap.FixedBufferAllocator.init(&buf);
    var log_allocator = log_fb.allocator();

    _ = scope;
    const str = std.fmt.allocPrintZ(log_allocator, format, args) catch {
        const fail_str: []const u8 = "Failed to allocate log string!";
        bind.logExt(&fail_str[0], fail_str.len, @intFromEnum(std.log.Level.err));
        return;
    };

    bind.logExt(&str[0], str.len, @intFromEnum(level));
}

pub const std_options = struct {
    pub const log_level = .debug;
    pub const logFn = wasmLogFn;
};

//------------------------------
//~ ojf: generico types

pub const Vec2 = @Vector(2, f32);

pub inline fn splatF(f: f32) Vec2 {
    return @splat(f);
}

pub fn mag(vec: Vec2) f32 {
    return @sqrt(vec[0] * vec[0] + vec[1] * vec[1]);
}

pub fn normalize(vec: Vec2) Vec2 {
    return vec / splatF(mag(vec));
}

pub fn dot(a: Vec2, b: Vec2) f32 {
    return a[0] * b[0] + a[1] * b[1];
}

pub fn clampVec(a: Vec2, lower_bound: Vec2, upper_bound: Vec2) Vec2 {
    return @max(@min(a, upper_bound), lower_bound);
}

pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,

    pub const red = fromHex(0xab3722);
    pub const blue = fromHex(0x263cab);
    pub const green = fromHex(0x36a632);
    pub const purple = fromHex(0x732c91);
    pub const orange = fromHex(0xe05600);
    pub const brown = fromHex(0x4a2d1a);
    pub const yellow = fromHex(0xf5f06e);
    pub const dark_grey = fromHex(0x1c1b18);
    pub const light_grey = fromHex(0x636363);
    pub const white = fromHex(0xffffff);
    pub const dark_green = fromHex(0x081f0b);

    pub inline fn fromHex(hex: u32) Color {
        return .{
            .r = @as(f32, @floatFromInt((hex & 0xFF0000) >> 16)) / 128,
            .g = @as(f32, @floatFromInt((hex & 0xFF00) >> 8)) / 128,
            .b = @as(f32, @floatFromInt(hex & 0xFF)) / 128,
            .a = 1,
        };
    }
};

//------------------------------
//~ ojf: game state

const InputState = struct {
    mouse_pos: Vec2,
    mouse_moving_frames: u8,

    mouse_l_clicked_frames: u8,
    mouse_l_down: bool,

    mouse_r_clicked_frames: u8,
    mouse_r_down: bool,

    forwards_down: bool,
    backwards_down: bool,
    left_down: bool,
    right_down: bool,

    pub inline fn wasLeftMouseClicked(self: *InputState) bool {
        if (self.mouse_l_clicked_frames > 0) {
            self.mouse_l_clicked_frames = 0;
            return true;
        }

        return false;
    }

    pub inline fn wasRightMouseClicked(self: *InputState) bool {
        if (self.mouse_r_clicked_frames > 0) {
            self.mouse_r_clicked_frames = 0;
            return true;
        }

        return false;
    }

    pub inline fn isMouseMoving(self: *InputState) bool {
        return self.mouse_moving_frames > 0;
    }

    pub fn isMouseHoveringRect(self: *InputState, pos: Vec2, size: Vec2) bool {
        const left = pos[0] - size[0] / 2;
        const right = pos[0] + size[0] / 2;
        const top = pos[1] + size[1] / 2;
        const bottom = pos[1] - size[1] / 2;

        return left < self.mouse_pos[0] and self.mouse_pos[0] < right and
            bottom < self.mouse_pos[1] and self.mouse_pos[1] < top;
    }

    pub fn isMouseHoveringCircle(self: *InputState, pos: Vec2, size: f32) bool {
        return mag(pos - self.mouse_pos) < size / 2;
    }

    pub fn isMouseHoveringEntity(self: *InputState, entity: *Entity) bool {
        if (entity.shape) |shape| {
            switch (shape) {
                .circle => {
                    return self.isMouseHoveringCircle(entity.pos, entity.size[0]);
                },
                .rect => {
                    return self.isMouseHoveringRect(entity.pos, entity.size);
                },
            }
        }
        return false;
    }
};

pub const TextureID = u32;

pub const Sprites = struct {
    long_table: TextureID,
    round_table: TextureID,
    pan: TextureID,
    pan_ring: TextureID,
    pan_fire: TextureID,
    heart: TextureID,
    counter: TextureID,
    red_bin: TextureID,
    green_bin: TextureID,
    purple_bin: TextureID,
    blue_bin: TextureID,
    red_ingredient: TextureID,
    green_ingredient: TextureID,
    purple_ingredient: TextureID,
    blue_ingredient: TextureID,
    seat: TextureID,
    dialog: TextureID,
    angry_dialog: TextureID,
    utensils: TextureID,
    background: TextureID,
    projectile: TextureID,
    menu: TextureID,
    cursor_open: TextureID,
    cursor_closed: TextureID,
    play_button: TextureID,
    play_button_hover: TextureID,
    player: TextureID,
    monster1: TextureID,
    monster2: TextureID,
    monster3: TextureID,
    dish_poop: TextureID,
};

fn loadSprite(path: []const u8) TextureID {
    return bind.loadTexture(&path[0], path.len);
}

fn loadSprites() Sprites {
    return Sprites{
        .long_table = loadSprite("assets/long_table.png"),
        .round_table = loadSprite("assets/round_table.png"),
        .pan = loadSprite("assets/pan.png"),
        .pan_ring = loadSprite("assets/pan_ring.png"),
        .pan_fire = loadSprite("assets/pan_fire.png"),
        .heart = loadSprite("assets/heart.png"),
        .counter = loadSprite("assets/counter.png"),
        .red_bin = loadSprite("assets/red_bin.png"),
        .blue_bin = loadSprite("assets/blue_bin.png"),
        .purple_bin = loadSprite("assets/purple_bin.png"),
        .green_bin = loadSprite("assets/green_bin.png"),
        .red_ingredient = loadSprite("assets/red_ingredient.png"),
        .blue_ingredient = loadSprite("assets/blue_ingredient.png"),
        .purple_ingredient = loadSprite("assets/purple_ingredient.png"),
        .green_ingredient = loadSprite("assets/green_ingredient.png"),
        .seat = loadSprite("assets/seat.png"),
        .dialog = loadSprite("assets/dialog.png"),
        .angry_dialog = loadSprite("assets/angry_dialog.png"),
        .utensils = loadSprite("assets/utensils.png"),
        .background = loadSprite("assets/background.png"),
        .projectile = loadSprite("assets/projectile.png"),
        .menu = loadSprite("assets/start_menu.png"),
        .cursor_open = loadSprite("assets/cursor_open.png"),
        .cursor_closed = loadSprite("assets/cursor_closed.png"),
        .play_button = loadSprite("assets/play_button.png"),
        .play_button_hover = loadSprite("assets/play_button_hover.png"),
        .player = loadSprite("assets/player.png"),
        .monster1 = loadSprite("assets/monster1.png"),
        .monster2 = loadSprite("assets/monster2.png"),
        .monster3 = loadSprite("assets/monster3.png"),
        .dish_poop = loadSprite("assets/dish_poop.png"),
    };
}

pub const EntityTypeIterator = struct {
    id: EntityID = 0,
    tag: EntityTag,
    game_state: *GameState,

    pub fn next(
        self: *EntityTypeIterator,
    ) ?EntityID {
        while (self.id < max_entities and
            (self.game_state.getEntity(self.id).tag != self.tag or
            !self.game_state.getEntity(self.id).active))
        {
            self.id += 1;
        }

        if (self.id >= max_entities) {
            return null;
        } else {
            defer self.id += 1;
            return self.id;
        }
    }

    pub fn init(game_state: *GameState, tag: EntityTag) EntityTypeIterator {
        return EntityTypeIterator{
            .tag = tag,
            .game_state = game_state,
        };
    }
};

pub const GameState = struct {
    input: InputState,

    arena: std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,

    temp_arena: std.heap.ArenaAllocator,
    temp_allocator: std.mem.Allocator,

    in_menu: bool,
    paused: bool,

    render_queue: RenderQueue,

    sprites: Sprites,

    previous_timestamp: i32,
    width: i32,
    height: i32,

    player: EntityID,

    next_customer: f32,

    colliders: ColliderList,
    entities: [max_entities]Entity,

    pub inline fn getPlayer(self: *GameState) *Entity {
        return &self.entities[self.player];
    }

    pub inline fn getEntity(self: *GameState, id: EntityID) *Entity {
        return &self.entities[id];
    }
};

const MyOtherStruct = struct {
    baz: bool,
    bop: f64,
};

const MyStruct = struct {
    foo: i32,
    bar: f32,
};

//------------------------------
//~ ojf: init

export fn onInit(width: c_int, height: c_int) *GameState {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var allocator = arena.allocator();

    var temp_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var temp_allocator = arena.allocator();

    var game_state: *GameState = allocator.create(GameState) catch {
        @panic("Failed to allocate game state!");
    };

    const sprites = loadSprites();

    game_state.* = GameState{
        .arena = arena,
        .allocator = allocator,
        .temp_arena = temp_arena,
        .temp_allocator = temp_allocator,
        .in_menu = true,
        .paused = false,
        .previous_timestamp = 0,
        .width = width,
        .height = height,
        .player = 0,
        .next_customer = 0,
        .sprites = sprites,
        .input = .{
            .mouse_pos = .{ 0, 0 },
            .mouse_moving_frames = 0,
            .mouse_l_clicked_frames = mouse_clicked_frames,
            .mouse_l_down = false,
            .mouse_r_clicked_frames = mouse_clicked_frames,
            .mouse_r_down = false,
            .forwards_down = false,
            .backwards_down = false,
            .left_down = false,
            .right_down = false,
        },
        .render_queue = RenderQueue.init(temp_allocator),
        .colliders = .{},
        .entities = std.mem.zeroes([max_entities]Entity),
    };

    game_state.player = entities.createPlayer(game_state);

    {
        const h: f32 = @floatFromInt(game_state.height);
        const w: f32 = @floatFromInt(game_state.width);
        //- ojf: counter
        _ = entities.createEntity(game_state, Entity{
            .pos = .{ 200, h / 2.0 },
            .size = .{ 100, 420 },
            .shape = .rect,
            .sprite = sprites.counter,
            .collider = .{
                .shape = .{ .aabb = .{ 75, 400 } },
                .mask = .terrain,
            },
        });

        entities.createIngredientBins(game_state);
        entities.createStoves(game_state);

        //- ojf: tables

        { //- ojf: square table
            const pos = Vec2{ 425, h / 2 };
            _ = entities.createEntity(game_state, Entity{
                .pos = pos,
                .size = long_table_size,
                .shape = .rect,
                .sprite = sprites.long_table,
                .collider = .{
                    .shape = .{ .aabb = long_table_collider_size },
                    .mask = .terrain,
                },
            });

            const size = long_table_collider_size;
            const left_x = pos[0] - size[0] / 2 - seat_offset_x;
            const right_x = pos[0] + size[0] / 2 + seat_offset_x;

            const seat_positions = [_]Vec2{
                .{ left_x, pos[1] + size[1] / 2 - seat_offset_y },
                .{ left_x, pos[1] },
                .{ left_x, pos[1] - size[1] / 2 + seat_offset_y },
                .{ right_x, pos[1] + size[1] / 2 - seat_offset_y },
                .{ right_x, pos[1] },
                .{ right_x, pos[1] - size[1] / 2 + seat_offset_y },
            };
            const dish_target_offsets = [_]Vec2{
                .{ seat_dish_target_offset, 0 },
            } ** 3 ++ [_]Vec2{
                .{ -seat_dish_target_offset, 0 },
            } ** 3;

            for (seat_positions, dish_target_offsets) |seat_pos, dish_target| {
                entities.createSeat(game_state, seat_pos, dish_target);
            }
        }
        _ = entities.createEntity(game_state, Entity{
            .pos = .{ 900, 175 },
            .size = @splat(round_table_size),
            .shape = .circle,
            .sprite = sprites.round_table,
            .collider = .{
                .shape = .{ .circle = round_table_collider_size },
                .mask = .terrain,
            },
        });
        _ = entities.createEntity(game_state, Entity{
            .pos = .{ 900, h - 175 },
            .size = @splat(round_table_size),
            .shape = .circle,
            .sprite = sprites.round_table,
            .collider = .{
                .shape = .{ .circle = round_table_collider_size },
                .mask = .terrain,
            },
        });

        _ = entities.createEntity(game_state, Entity{
            .pos = .{ 670, h / 2 },
            .size = @splat(round_table_size),
            .shape = .circle,
            .sprite = sprites.round_table,
            .collider = .{
                .shape = .{ .circle = round_table_collider_size },
                .mask = .terrain,
            },
        });

        //- ojf: walls
        _ = entities.createEntity(game_state, Entity{
            .pos = .{ -50, h / 2.0 },
            .size = .{ 120, h },
            .shape = .rect,
            .color = Color.dark_green,
            .collider = .{
                .shape = .{ .aabb = .{ 120, h } },
                .mask = .terrain,
            },
        });
        _ = entities.createEntity(game_state, Entity{
            .pos = .{ w + 50, h / 2.0 },
            .size = .{ 120, h },
            .shape = .rect,
            .color = Color.dark_green,
            .collider = .{
                .shape = .{ .aabb = .{ 120, h } },
                .mask = .terrain,
            },
        });
        _ = entities.createEntity(game_state, Entity{
            .pos = .{ w / 2, -50 },
            .size = .{ w, 120 },
            .shape = .rect,
            .color = Color.dark_green,
            .collider = .{
                .shape = .{ .aabb = .{ w, 120 } },
                .mask = .terrain,
            },
        });
        _ = entities.createEntity(game_state, Entity{
            .pos = .{ w / 2, h + 50 },
            .size = .{ w, 120 },
            .shape = .rect,
            .color = Color.dark_green,
            .collider = .{
                .shape = .{ .aabb = .{ w, 120 } },
                .mask = .terrain,
            },
        });
    }
    return game_state;
}

//------------------------------
//~ ojf: input handling

fn handleKeyEvent(
    game_state: *GameState,
    code: bind.KeyCode,
    state: bool,
) void {
    const input_state = &game_state.input;
    switch (code) {
        .key_w => {
            input_state.forwards_down = state;
        },
        .key_a => {
            input_state.left_down = state;
        },
        .key_s => {
            input_state.backwards_down = state;
        },
        .key_d => {
            input_state.right_down = state;
        },
        .key_p => {
            if (state) {
                game_state.paused = !game_state.paused;
                dlog("PAUSED: {}", .{game_state.paused});
            }
        },
        .mouse_l => {
            dlog("{d:.2}", .{input_state.mouse_pos});
            input_state.mouse_l_down = state;
            if (state) {
                input_state.mouse_l_clicked_frames = mouse_clicked_frames;
            }
        },
        .mouse_r => {
            input_state.mouse_r_down = state;
            if (state) {
                input_state.mouse_r_clicked_frames = mouse_clicked_frames;
            }
        },
    }
}

export fn handleEvent(
    game_state: *GameState,
    event_type: bind.EventType,
    key_code: bind.KeyCode,
) void {
    switch (event_type) {
        .button_down => {
            handleKeyEvent(game_state, key_code, true);
        },
        .button_up => {
            handleKeyEvent(game_state, key_code, false);
        },
    }
}

export fn handleMouse(
    game_state: *GameState,
    x: f32,
    y: f32,
) void {
    game_state.input.mouse_moving_frames = mouse_moving_frames;

    game_state.input.mouse_pos = game_state.input.mouse_pos + Vec2{ x, -y };
}

//------------------------------
//~ ojf: main loop

fn processMenu(game_state: *GameState, delta: f32) void {
    _ = delta;
    game_state.render_queue = RenderQueue.init(game_state.temp_allocator);

    //- ojf: draw background
    render.drawSprite(
        game_state,
        Vec2{
            @as(f32, @floatFromInt(game_state.width)) / 2.0,
            @as(f32, @floatFromInt(game_state.height)) / 2.0,
        },
        Vec2{
            @floatFromInt(game_state.width),
            @floatFromInt(game_state.height),
        },
        -10,
        game_state.sprites.menu,
    );

    //- ojf: draw mouse
    if (game_state.input.mouse_l_down) {
        render.drawSprite(
            game_state,
            game_state.input.mouse_pos,
            @splat(cursor_size),
            100,
            game_state.sprites.cursor_closed,
        );
    } else {
        render.drawSprite(
            game_state,
            game_state.input.mouse_pos,
            @splat(cursor_size),
            100,
            game_state.sprites.cursor_open,
        );
    }

    if (game_state.input.isMouseHoveringRect(start_button_pos, start_button_size)) {
        render.drawSprite(
            game_state,
            start_button_pos,
            start_button_size,
            10,
            game_state.sprites.play_button_hover,
        );

        if (game_state.input.wasLeftMouseClicked()) {
            game_state.in_menu = false;
        }
    } else {
        render.drawSprite(
            game_state,
            start_button_pos,
            start_button_size,
            10,
            game_state.sprites.play_button,
        );
    }

    bind.clear();

    var render_queue_iter = render.RenderQueueIter.init(game_state.render_queue);
    while (render_queue_iter.next()) |command| {
        command.execute();
    }

    if (!game_state.temp_arena.reset(.retain_capacity)) {
        std.log.warn("Failed to reset temporary arena!", .{});
    }
}

export fn onAnimationFrame(game_state: *GameState, timestamp: c_int) void {
    const delta: f32 = if (game_state.previous_timestamp > 0)
        @as(f32, @floatFromInt(timestamp - game_state.previous_timestamp)) / 1000.0
    else
        0;
    defer game_state.previous_timestamp = timestamp;

    //- ojf: update input state
    if (game_state.input.mouse_l_clicked_frames > 0) {
        game_state.input.mouse_l_clicked_frames -= 1;
    }
    if (game_state.input.mouse_r_clicked_frames > 0) {
        game_state.input.mouse_r_clicked_frames -= 1;
    }
    if (game_state.input.mouse_moving_frames > 0) {
        game_state.input.mouse_moving_frames -= 1;
    }

    if (game_state.in_menu) {
        processMenu(game_state, delta);
        return;
    }

    const paused_this_frame = game_state.paused;

    //- ojf: create render queue.  we safely discard the existing queue,
    // because all of its underlying memory was dealloced at the end of
    // the previous frame
    if (!paused_this_frame) {
        game_state.render_queue = RenderQueue.init(game_state.temp_allocator);
    }

    //- ojf: update entities
    if (!paused_this_frame) {
        entities.spawnCustomers(game_state, delta);

        render.drawSprite(
            game_state,
            Vec2{
                @as(f32, @floatFromInt(game_state.width)) / 2.0,
                @as(f32, @floatFromInt(game_state.height)) / 2.0,
            },
            Vec2{
                @floatFromInt(game_state.width),
                @floatFromInt(game_state.height),
            },
            -10,
            game_state.sprites.background,
        );

        var active: u32 = 0;
        for (&game_state.entities) |*entity| {
            entity.process(game_state, delta);
            if (entity.active) {
                active += 1;
            }
        }

        hud.drawHud(game_state);
    }
    // dlog("ACTIVE ENTITIES: {}", .{active});

    //- ojf: render
    bind.clear();

    var render_queue_iter = render.RenderQueueIter.init(game_state.render_queue);
    while (render_queue_iter.next()) |command| {
        command.execute();
    }

    //- ojf: reset arena
    if (!paused_this_frame) {
        if (!game_state.temp_arena.reset(.retain_capacity)) {
            std.log.warn("Failed to reset temporary arena!", .{});
        }
    }
}
