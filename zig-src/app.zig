const std = @import("std");
const ch32 = @import("ch32.zig");
const hal = ch32.hal;
const debug = @import("debug.zig");
const tick = @import("tick.zig");
const lcd = @import("lcd.zig");
const event = @import("event.zig");
const ui = @import("ui/ui.zig");
const utils = @import("utils.zig");
const Color = ui.Color565;

var ui_pool: [24 * 1024]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&ui_pool);

var dvd_dx: i32 = 3;
var dvd_dy: i32 = 2;
var dvd_color: Color = Color.BLUE;
var target_color: Color = Color.BLUE;

var target_yaw: f32 = 0;
var target_pitch: f32 = 0;
const decay: f32 = 0.10;

var tex_buf: [18 * 12]u16 = undefined;
var tex_dirty: bool = true;

const cube_vertices = utils.createCubeVertices(20);
const cube_edges = utils.autoGenEdges(&cube_vertices, 20.5);

var pv: [8]ui.TexVertex = undefined;

fn drawScene(r: *ui.Renderer3D, canvas: *ui.Canvas) void {
    for (cube_edges) |edge| {
        canvas.drawLine(
            @intFromFloat(pv[edge[0]].x),
            @intFromFloat(pv[edge[0]].y),
            @intFromFloat(pv[edge[1]].x),
            @intFromFloat(pv[edge[1]].y),
            dvd_color,
        );
    }

    const m = ui.FontSize.px12.metrics();
    const tex_w: i32 = @as(i32, @intCast(3)) * m.w;
    const tex_h: i32 = m.h;
    if (tex_dirty) {
        @memset(&tex_buf, 0x07E0);
        r.compositeText(&tex_buf, @intCast(tex_w), 0, 0, "DVD", .px12, dvd_color);
        tex_dirty = false;
    }

    const tw_f: f32 = @floatFromInt(tex_w);
    const th_f: f32 = @floatFromInt(tex_h);
    const key: u16 = 0x07E0;

    r.drawTexTriangle(
        .{ .x = pv[4].x, .y = pv[4].y, .z = pv[4].z, .u = tw_f, .v = 0 },
        .{ .x = pv[5].x, .y = pv[5].y, .z = pv[5].z, .u = 0, .v = 0 },
        .{ .x = pv[7].x, .y = pv[7].y, .z = pv[7].z, .u = tw_f, .v = th_f },
        &tex_buf,
        tex_w,
        tex_h,
        tex_w,
        key,
    );
    r.drawTexTriangle(
        .{ .x = pv[5].x, .y = pv[5].y, .z = pv[5].z, .u = 0, .v = 0 },
        .{ .x = pv[6].x, .y = pv[6].y, .z = pv[6].z, .u = 0, .v = th_f },
        .{ .x = pv[7].x, .y = pv[7].y, .z = pv[7].z, .u = tw_f, .v = th_f },
        &tex_buf,
        tex_w,
        tex_h,
        tex_w,
        key,
    );
}

fn formatTitleText(gpa: std.mem.Allocator) []const u8 {
    return std.fmt.allocPrint(
        gpa,
        "Zig Tree UI & DVD Demo @ {}",
        .{@as(*volatile u32, &lcd.impl.dma_tc_counter).*},
    ) catch "Zig Tree UI & DVD Demo";
}

pub fn run() void {
    const gpa = fba.allocator();

    var display = ui.Display.init(gpa, 16) catch unreachable;
    display.bind();

    const title = display.addToScreen(ui.widgets.MarqueeLabel, .{
        .area = ui.rect(0, 0, lcd.WIDTH, 20),
        .text = formatTitleText(gpa),
        .bg_color = Color.WHITE,
        .color = Color.BLACK,
        .gap = 24,
        .offset = lcd.WIDTH,
    }) catch unreachable;

    var renderer = display.addToScreen(ui.Renderer3D, .{
        .area = ui.rect(20, 20, 120, 120),
    }) catch unreachable;
    renderer.user_draw = drawScene;
    const dvd_node = renderer.asNode();

    const items: [4]ui.widgets.List.Item = .{
        .{ .tag = "hello", .discption = null, .ref = null },
        .{ .tag = "hello2", .discption = null, .ref = null },
        .{ .tag = "hello3", .discption = null, .ref = null },
        .{ .tag = "hello4", .discption = null, .ref = null },
    };
    const list = display.addToScreen(ui.widgets.List, .{ .area = ui.rect(20, 40, 60, 120), .items = &items }) catch unreachable;

    lcd.fill(0, 0, lcd.WIDTH, lcd.HEIGHT, Color.BLACK.toRgb565());

    var led_on = false;
    var last_frame: u32 = 0;

    while (true) {
        // 事件处理
        while (true) {
            const ev = event.poll();
            switch (ev) {
                .quit => return,
                .rotation => |r| {
                    target_yaw += r.yaw;
                    target_pitch += r.pitch;
                    debug.print("target yaw={d} pitch={d}\r\n", .{ target_yaw, target_pitch });
                },
                .none => break,
            }
        }

        const now = tick.millis();
        if (now -% last_frame >= 16) {
            last_frame = now;

            title.setText(formatTitleText(gpa));
            title.step(-2);

            renderer.yaw = utils.lerp(f32, renderer.yaw, target_yaw, decay);
            renderer.pitch = utils.lerp(f32, renderer.pitch, target_pitch, decay);

            if (dvd_color.toRgb565() != target_color.toRgb565()) {
                dvd_color = utils.lerpColor(dvd_color, target_color, decay);
                tex_dirty = true;
            }

            var new_x = dvd_node.area.x + dvd_dx;
            var new_y = dvd_node.area.y + dvd_dy;

            const min_y = title.asNode().area.h;
            var hit = false;

            if (new_x <= 0) {
                new_x = 0;
                dvd_dx = -dvd_dx;
                target_yaw += @as(f32, @floatFromInt(utils.randRange(20, 60)));
                hit = true;
            } else if (new_x + dvd_node.area.w >= lcd.WIDTH) {
                new_x = lcd.WIDTH - dvd_node.area.w;
                dvd_dx = -dvd_dx;
                target_yaw -= @as(f32, @floatFromInt(utils.randRange(20, 60)));
                hit = true;
            }

            if (new_y <= min_y) {
                new_y = min_y;
                dvd_dy = -dvd_dy;
                target_pitch += @as(f32, @floatFromInt(utils.randRange(20, 60)));
                hit = true;
            } else if (new_y + dvd_node.area.h >= lcd.HEIGHT) {
                new_y = lcd.HEIGHT - dvd_node.area.h;
                dvd_dy = -dvd_dy;
                target_pitch -= @as(f32, @floatFromInt(utils.randRange(20, 60)));
                hit = true;
            }

            if (hit) {
                led_on = !led_on;
                hal.GPIO_WriteBit(hal.GPIOA, hal.GPIO_Pin_3, if (led_on) hal.Bit_SET else hal.Bit_RESET);

                if (dvd_dx > 0 and dvd_dy > 0) {
                    target_color = Color.BLUE;
                } else if (dvd_dx < 0 and dvd_dy > 0) {
                    target_color = Color.RED;
                } else if (dvd_dx > 0 and dvd_dy < 0) {
                    target_color = Color.MAGENTA;
                } else {
                    target_color = Color.CYAN;
                }
                debug.print("DVD hit! New direction: ({}, {}), Color: {}\r\n", .{ dvd_dx, dvd_dy, dvd_color });
                list.select(@intCast(utils.randRange(0, 3)));
            }

            dvd_node.setPos(new_x, new_y);
            list.update();
            renderer.updateDirty(&cube_vertices, &pv);
            display.render();
        }
    }
}
