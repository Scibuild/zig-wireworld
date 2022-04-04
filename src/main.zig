const std = @import("std");
const gk = @import("gamekit");
const gfx = gk.gfx;
const math = gk.math;
const Vec2 = math.Vec2;
const Mat32 = math.Mat32;

const Camera2D = struct {
    pos: Vec2,
    rot: f32,
    zoom: f32,
    // marks whether the matrix needs to be updated
    dirty: bool,
    matrix: Mat32,

    pub fn init() Camera2D {
        return .{
            .pos = .{ .x = 0, .y = 0 },
            .rot = 0,
            .zoom = 1,
            .dirty = true,
            .matrix = Mat32.init(),
        };
    }

    const Self = @This();
    pub fn updateMatrix(self: *Self) Mat32 {
        //        if (!self.dirty) {
        //            return self.matrix;
        //        }

        self.matrix.setTransform(.{
            .angle = -self.rot,
            .sx = self.zoom,
            .sy = self.zoom,
            .ox = self.pos.x,
            .oy = self.pos.y,
            .x = @intToFloat(f32, gk.window.width()) / 2,
            .y = @intToFloat(f32, gk.window.height()) / 2,
        });

        return self.matrix;
    }

    pub fn translate(self: *Self, vec: Vec2) void {
        self.pos = self.pos.addv(vec);
        self.dirty = true;
    }

    // changing zoom linearly feels wrong, lets change proportionally
    pub fn changeZoom(self: *Self, zoom: f32) void {
        self.zoom += zoom * self.zoom;
        self.dirty = true;
    }

    pub fn setZoom(self: *Self, zoom: f32) void {
        self.zoom = zoom;
        self.dirty = true;
    }

    pub fn setPosition(self: *Self, pos: Vec2) void {
        self.pos = pos;
        self.dirty = true;
    }

    pub fn screenToWorldCoords(self: *Self, pos: Vec2) Vec2 {
        return self.matrix.invert().transformVec2(pos);
    }

    pub fn mouseWorldPos(self: *Self) Vec2 {
        return self.screenToWorldCoords(gk.input.mousePos());
    }
};

const Cell = enum {
    empty,
    strong_wire,
    strong_head,
    strong_tail,
    weak_wire,
    weak_head,
    weak_tail,

    pub fn toColor(self: @This()) ?math.Color {
        return switch (self) {
            .strong_wire => math.Color.gray,
            .strong_head => math.Color.yellow,
            .strong_tail => math.Color.gold,
            .weak_wire => math.Color.maroon,
            .weak_head => math.Color.blue,
            .weak_tail => math.Color.sky_blue,
            .empty => null,
        };
    }

    // pub fn nextState(self: @This(), row_above: []Cell, row_of: []Cell, row_bellow: []Cell) Cell {
    //     switch (front_buffer[loc]) {
    //         .empty => return .empty,
    //         .head => return .tail,
    //         .tail => return .wire,
    //         .wire => {
    //             // need to handle literal edge cases
    //             if (x == 0 or y == 0 or x == grid_width - 1 or y == grid_height - 1)
    //                 break :brk Cell.wire;

    //             var num_neighbours: u32 = 0;
    //             for (row_above) |c|
    //                 if (c == .head) num_neighbours += 1;
    //             for (row_of) |c|
    //                 if (c == .head) num_neighbours += 1;
    //             for (row_bellow) |c|
    //                 if (c == .head) num_neighbours += 1;

    //             if (num_neighbours == 1 or num_neighbours == 2) {
    //                 return .head;
    //             } else {
    //                 return .wire;
    //             }
    //         },
    //     }
    // }
};

const Game = struct {
    grid_shown: bool = true,
    playing: bool = false,
    time_since_last_step: f64 = 0,

    is_cell_buffer_1: bool = true,
    cell_buffer_1: [grid_width * grid_height]Cell = [_]Cell{.empty} ** (grid_width * grid_height),
    cell_buffer_2: [grid_width * grid_height]Cell = [_]Cell{.empty} ** (grid_width * grid_height),

    pub const grid_height = 256;
    pub const grid_width = 256;

    pub fn getCellBuffer(self: *@This()) []Cell {
        return if (self.is_cell_buffer_1) self.cell_buffer_1[0..] else self.cell_buffer_2[0..];
    }

    pub fn getGridSquare(self: *@This(), x: i64, y: i64) ?*Cell {
        const gx = x + Game.grid_width / 2;
        const gy = y + Game.grid_height / 2;
        if (gx < 0 or gx >= grid_width or gy < 0 or gy >= grid_height) return null;
        // many potentiall optimisations here
        return &(self.getCellBuffer()[@intCast(usize, gx + gy * grid_width)]);
    }

    pub fn worldPosToGridSquare(_: *@This(), p: Vec2) struct { x: i64, y: i64 } {
        const grid_x = @floatToInt(i64, @floor(p.x / grid_spacing));
        const grid_y = @floatToInt(i64, @floor(p.y / grid_spacing));
        return .{ .x = grid_x, .y = grid_y };
    }

    pub fn computeStep(self: *@This()) void {
        var front_buffer = if (self.is_cell_buffer_1) self.cell_buffer_1[0..] else self.cell_buffer_2[0..];
        var back_buffer = if (self.is_cell_buffer_1) self.cell_buffer_2[0..] else self.cell_buffer_1[0..];
        self.is_cell_buffer_1 = !self.is_cell_buffer_1;
        var x: usize = 0;
        while (x < grid_width) : (x += 1) {
            var y: usize = 0;
            while (y < grid_height) : (y += 1) {
                const loc = x + y * grid_width;
                const new_cell = switch (front_buffer[loc]) {
                    .empty => .empty,
                    .strong_head => .strong_tail,
                    .weak_head => .weak_tail,
                    .strong_tail => .strong_wire,
                    .weak_tail => .weak_wire,
                    .strong_wire => brk: {
                        // need to handle literal edge cases
                        if (x == 0 or y == 0 or x == grid_width - 1 or y == grid_height - 1)
                            break :brk Cell.strong_wire;
                        const num_strong = numCellsAround(.strong_head, x, y, front_buffer, grid_width);
                        const num_weak = numCellsAround(.weak_head, x, y, front_buffer, grid_width);

                        if (num_strong == 1 or num_strong == 2 or num_weak == 2) {
                            break :brk Cell.strong_head;
                        } else {
                            break :brk Cell.strong_wire;
                        }
                    },
                    .weak_wire => brk: {
                        // need to handle literal edge cases
                        if (x == 0 or y == 0 or x == grid_width - 1 or y == grid_height - 1)
                            break :brk Cell.weak_wire;
                        const num_strong = numCellsAround(.strong_head, x, y, front_buffer, grid_width);
                        const num_weak = numCellsAround(.weak_head, x, y, front_buffer, grid_width);

                        if (num_strong == 1 or num_weak == 1 or num_weak == 2) {
                            break :brk Cell.weak_head;
                        } else {
                            break :brk Cell.weak_wire;
                        }
                    },
                };
                back_buffer[loc] = new_cell;
            }
        }
    }
};

pub fn numCellsAround(cell_type: Cell, x: usize, y: usize, buffer: []Cell, stride: usize) u32 {
    var num_neighbours: u32 = 0;
    for (buffer[x - 1 + (y - 1) * stride .. x + 2 + (y - 1) * stride]) |c| {
        if (c == cell_type) num_neighbours += 1;
    }
    for (buffer[x - 1 + (y) * stride .. x + 2 + (y) * stride]) |c| {
        if (c == cell_type) num_neighbours += 1;
    }
    for (buffer[x - 1 + (y + 1) * stride .. x + 2 + (y + 1) * stride]) |c| {
        if (c == cell_type) num_neighbours += 1;
    }
    return num_neighbours;
}

var camera: Camera2D = undefined;
var game: Game = undefined;

pub fn main() anyerror!void {
    try gk.run(.{
        .init = init,
        .update = update,
        .render = render,
    });
}

fn init() !void {
    camera = Camera2D.init();
    game = Game{};
}

fn update() !void {
    const dt = gk.time.dt();
    const zoom_speed = 3.0;
    camera.changeZoom(dt * @intToFloat(f32, gk.input.mouse_wheel_y) * zoom_speed);

    if (gk.input.keyDown(.space)) {
        camera.translate(Vec2{
            .x = @intToFloat(f32, -gk.input.mouse_rel_x) / camera.zoom,
            .y = @intToFloat(f32, -gk.input.mouse_rel_y) / camera.zoom,
        });
    }

    if (gk.input.keyPressed(.g)) {
        game.grid_shown = !game.grid_shown;
    }

    if (gk.input.keyPressed(.s)) {
        game.computeStep();
    }

    if (gk.input.keyPressed(.p)) {
        game.playing = !game.playing;
    }

    if (game.playing) {
        if (game.time_since_last_step > 0.1) {
            game.computeStep();
            game.time_since_last_step = game.time_since_last_step - 0.1;
        } else {
            game.time_since_last_step += dt;
        }
    }

    const left_down = gk.input.mouseDown(.left);
    const right_down = gk.input.mouseDown(.right);
    const middle_down = gk.input.mouseDown(.middle);
    const r_down = gk.input.keyDown(.r);
    const t_down = gk.input.keyDown(.t);
    const e_down = gk.input.keyDown(.e);
    const w_down = gk.input.keyDown(.w);
    const q_down = gk.input.keyDown(.q);
    if (left_down or right_down or middle_down or r_down or t_down or e_down or q_down or w_down) {
        const mousePos = camera.screenToWorldCoords(gk.input.mousePos());
        const square = game.worldPosToGridSquare(mousePos);
        if (game.getGridSquare(square.x, square.y)) |cell| {
            if (left_down or w_down) cell.* = .strong_wire;
            if (q_down) cell.* = .weak_wire;
            if (right_down or e_down) cell.* = .empty;
            if (r_down) {
                switch (cell.*) {
                    .strong_wire, .strong_tail => cell.* = .strong_head,
                    .weak_wire, .weak_tail => cell.* = .weak_head,
                    else => {},
                }
            }
            if (t_down) {
                switch (cell.*) {
                    .strong_wire, .strong_head => cell.* = .strong_tail,
                    .weak_wire, .weak_head => cell.* = .weak_tail,
                    else => {},
                }
            }
        }
    }
}

fn render() !void {
    gfx.beginPass(.{
        .color = math.Color.black,
        .trans_mat = camera.updateMatrix(),
    });

    drawCells();

    if (game.grid_shown) {
        drawGrid();
    }

    gfx.endPass();
    gfx.beginPass(.{ .clear_color = false });
    gfx.draw.text("Q - weak wire", 40, 40, null);
    gfx.draw.text("W - strong wire", 40, 70, null);
    gfx.draw.text("E - empty", 40, 100, null);
    gfx.draw.text("R - head", 40, 130, null);
    gfx.draw.text("T - tail", 40, 160, null);
    gfx.endPass();
}

const grid_spacing = 40;

fn drawGrid() void {
    var width = @intToFloat(f32, gk.window.width());
    var height = @intToFloat(f32, gk.window.height());

    var projected_top_left_corner = camera.screenToWorldCoords(Vec2{ .x = 0, .y = 0 });
    var projected_bottom_right_corner = camera.screenToWorldCoords(Vec2{ .x = width, .y = height });

    // fancy stuff to basically just align the grid squares with the actual grid rather than the screen
    var offset: f32 = (@divFloor(projected_top_left_corner.x, grid_spacing) + 1) * grid_spacing;

    // std.debug.print("offset x {}", .{offset});
    var lines_drawn: u64 = 0;

    const line_color = math.Color{ .comps = .{ .r = 40, .g = 40, .b = 40, .a = 255 } };

    while (offset < projected_bottom_right_corner.x) : (offset += grid_spacing) {
        gfx.draw.line(
            Vec2{ .x = offset, .y = projected_top_left_corner.y },
            Vec2{ .x = offset, .y = projected_bottom_right_corner.y },
            2,
            line_color,
        );
        lines_drawn += 1;
    }

    offset = (@divFloor(projected_top_left_corner.y, grid_spacing) + 1) * grid_spacing;
    // std.debug.print("offset y {}", .{offset});
    while (offset < projected_bottom_right_corner.y) : (offset += grid_spacing) {
        gfx.draw.line(
            Vec2{ .x = projected_top_left_corner.x, .y = offset },
            Vec2{ .x = projected_bottom_right_corner.x, .y = offset },
            2,
            line_color,
        );
        lines_drawn += 1;
    }
    // std.debug.print("bottom right: {}\t top left: {}\t lines_drawn: {}\n", .{ projected_bottom_right_corner, projected_top_left_corner, lines_drawn });
}

fn drawCells() void {
    var width = @intToFloat(f32, gk.window.width());
    var height = @intToFloat(f32, gk.window.height());
    var projected_top_left_corner = camera.screenToWorldCoords(Vec2{ .x = 0, .y = 0 });
    var projected_bottom_right_corner = camera.screenToWorldCoords(Vec2{ .x = width, .y = height });

    var grid_top_left = game.worldPosToGridSquare(projected_top_left_corner);
    var grid_bottom_right = game.worldPosToGridSquare(projected_bottom_right_corner);

    var cells_drawn: u32 = 0;

    var x = grid_top_left.x;
    while (x <= grid_bottom_right.x) : (x += 1) {
        var y = grid_top_left.y;
        while (y <= grid_bottom_right.y) : (y += 1) {
            var cell = game.getGridSquare(x, y) orelse continue;

            if (cell.* != .empty) {
                if (cell.toColor()) |col| {
                    gfx.draw.rect(
                        Vec2{
                            .x = (@intToFloat(f32, x)) * grid_spacing,
                            .y = (@intToFloat(f32, y)) * grid_spacing,
                        },
                        grid_spacing,
                        grid_spacing,
                        col,
                    );
                    cells_drawn += 1;
                }
            }
        }
    }

    // std.debug.print("cells drawn: {}                             \r", .{cells_drawn});

    //    const current_cell_buffer = if (game.is_cell_buffer_1) game.cell_buffer_1[0..] else game.cell_buffer_2[0..];
    //    for (current_cell_buffer) |v, i| {
    //        const x_coord = @intCast(i64, i % Game.grid_width) - @intCast(i64, Game.grid_width / 2);
    //        const y_coord = @intCast(i64, i / Game.grid_height) - @intCast(i64, Game.grid_height / 2);
    //
    //        switch (v) {
    //            .wire => gfx.draw.rect(
    //                Vec2{
    //                    .x = (@intToFloat(f32, x_coord)) * grid_spacing,
    //                    .y = (@intToFloat(f32, y_coord)) * grid_spacing,
    //                },
    //                grid_spacing,
    //                grid_spacing,
    //                math.Color.gray,
    //            ),
    //            else => {},
    //        }
    //    }
}
