const std = @import("std");
const ch32 = @import("ch32.zig");
const hal = ch32.hal;
const c = ch32.c;
const interrupt = @import("interrupt.zig");
const debug = @import("debug.zig");
const tick = @import("tick.zig");
const lcd = @import("lcd.zig");
const usb = @import("usb.zig");
const ui = @import("ui/ui.zig");
const utils = @import("utils.zig");
const Color = ui.Color565;

// Global memory pool for ALL UI objects (Display, DrawBuf, Nodes)
// 24KB pool: double-buffer (~15KB) + nodes + overhead
var ui_pool: [24 * 1024]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&ui_pool);

var dvd_dx: i32 = 3;
var dvd_dy: i32 = 2;
var dvd_color: Color = Color.BLUE;
var target_color: Color = Color.BLUE;

// 旋转目标 + 指数衰减动画
var target_yaw: f32 = 0;
var target_pitch: f32 = 0;
const decay: f32 = 0.10; // 每帧衰减比例（0~1，越大越快回弹）

// 纹理缓存：只在颜色变化时重建
var tex_buf: [18 * 12]u16 = undefined;
var tex_dirty: bool = true;

// USB 命令行缓冲区
var cmd_buf: [128]u8 = undefined;
var cmd_len: u32 = 0;

// 正方体顶点和边（comptime 生成）
const cube_vertices = utils.createCubeVertices(20);
const cube_edges = utils.autoGenEdges(&cube_vertices, 20.5);

var pv: [8]ui.TexVertex = undefined;

fn drawScene(r: *ui.Renderer3D, canvas: *ui.Canvas) void {
    // 画线框（临时截断为整数）
    for (cube_edges) |edge| {
        canvas.drawLine(
            @intFromFloat(pv[edge[0]].x),
            @intFromFloat(pv[edge[0]].y),
            @intFromFloat(pv[edge[1]].x),
            @intFromFloat(pv[edge[1]].y),
            dvd_color,
        );
    }

    // 纹理缓存：颜色变化时才重建
    const m = ui.FontSize.px12.metrics();
    const tex_w: i32 = @as(i32, @intCast(3)) * m.w;
    const tex_h: i32 = m.h;
    if (tex_dirty) {
        @memset(&tex_buf, 0x07E0);
        r.compositeText(&tex_buf, @intCast(tex_w), 0, 0, "DVD", .px12, dvd_color);
        tex_dirty = false;
    }

    // 背面剔除
    // if (!r.isFrontFace(pv[4], pv[5], pv[7])) return;

    // 纹理三角形光栅化
    const tw_f: f32 = @floatFromInt(tex_w);
    const th_f: f32 = @floatFromInt(tex_h);
    const key: u16 = 0x07E0;

    r.drawTexTriangle(
        .{ .x = pv[4].x, .y = pv[4].y, .z = pv[4].z, .u = 0, .v = 0 },
        .{ .x = pv[5].x, .y = pv[5].y, .z = pv[5].z, .u = tw_f, .v = 0 },
        .{ .x = pv[7].x, .y = pv[7].y, .z = pv[7].z, .u = 0, .v = th_f },
        &tex_buf,
        tex_w,
        tex_h,
        tex_w,
        key,
    );
    r.drawTexTriangle(
        .{ .x = pv[5].x, .y = pv[5].y, .z = pv[5].z, .u = tw_f, .v = 0 },
        .{ .x = pv[6].x, .y = pv[6].y, .z = pv[6].z, .u = tw_f, .v = th_f },
        .{ .x = pv[7].x, .y = pv[7].y, .z = pv[7].z, .u = 0, .v = th_f },
        &tex_buf,
        tex_w,
        tex_h,
        tex_w,
        key,
    );
}

fn parseFloat(buf: []const u8) ?struct { value: f32, consumed: u32 } {
    // 简易浮点解析
    var i: usize = 0;
    var negative = false;
    if (i < buf.len and (buf[i] == '-' or buf[i] == '+')) {
        negative = buf[i] == '-';
        i += 1;
    }
    var int_part: f32 = 0;
    while (i < buf.len and buf[i] >= '0' and buf[i] <= '9') {
        int_part = int_part * 10.0 + @as(f32, @floatFromInt(buf[i] - '0'));
        i += 1;
    }
    var frac_part: f32 = 0;
    var frac_div: f32 = 1.0;
    if (i < buf.len and buf[i] == '.') {
        i += 1;
        while (i < buf.len and buf[i] >= '0' and buf[i] <= '9') {
            frac_part = frac_part * 10.0 + @as(f32, @floatFromInt(buf[i] - '0'));
            frac_div *= 10.0;
            i += 1;
        }
    }
    if (i == 0) return null;
    const val = blk: {
        var v = int_part + frac_part / frac_div;
        if (negative) v = -v;
        break :blk v;
    };
    return .{ .value = val, .consumed = @intCast(i) };
}

fn parseRotationCmd(line: []const u8) void {
    // 协议: Y<yaw>,P<pitch>  例如 "Y10.5,P-5.2"
    var pos: usize = 0;

    // 跳过前导空白
    while (pos < line.len and line[pos] == ' ') pos += 1;

    while (pos < line.len) {
        if (line[pos] == 'Y' or line[pos] == 'y') {
            pos += 1;
            if (parseFloat(line[pos..])) |r| {
                target_yaw = r.value;
                pos += r.consumed;
            }
        } else if (line[pos] == 'P' or line[pos] == 'p') {
            pos += 1;
            if (parseFloat(line[pos..])) |r| {
                target_pitch = r.value;
                pos += r.consumed;
            }
        } else if (line[pos] == ',') {
            pos += 1;
        } else {
            break;
        }
    }

    debug.print("target yaw={d} pitch={d}\r\n", .{ target_yaw, target_pitch });
}

fn formatTitleText(gpa: std.mem.Allocator) []const u8 {
    return std.fmt.allocPrint(
        gpa,
        "Zig Tree UI & DVD Demo @ {}",
        .{@as(*volatile u32, &lcd.dma_tc_counter).*},
    ) catch "Zig Tree UI & DVD Demo";
}

pub export fn main() noreturn {
    const gpa = fba.allocator();
    ch32.init();
    tick.init();
    usb.init() catch |err| {
        debug.print("USB init failed: {}\r\n", .{err});
    };
    lcd.init();

    debug.print("hello from zig DVD tree-ui animation\r\n", .{});
    debug.print("USB rotation control: send Y<yaw>,P<pitch>\\n\r\n", .{});

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

    // 清屏
    lcd.fill(0, 0, lcd.WIDTH, lcd.HEIGHT, Color.BLACK.toRgb565());

    var led_on = false;
    var last_frame: u32 = 0;

    while (true) {
        // 处理 USB 串口数据
        const data = usb.task();
        var got_cmd = false;
        for (data) |b| {
            if (b == '\n' or b == '\r') {
                if (cmd_len > 0) {
                    parseRotationCmd(cmd_buf[0..cmd_len]);
                    cmd_len = 0;
                    got_cmd = true;
                }
            } else if (cmd_len < cmd_buf.len) {
                cmd_buf[cmd_len] = b;
                cmd_len += 1;
            }
        }

        const now = tick.millis();
        if (now -% last_frame >= 16) {
            last_frame = now;

            title.setText(formatTitleText(gpa));
            title.step(-2);

            // 旋转 lerp 动画
            renderer.yaw = utils.lerp(f32, renderer.yaw, target_yaw, decay);
            renderer.pitch = utils.lerp(f32, renderer.pitch, target_pitch, decay);

            // 颜色 lerp 动画
            if (dvd_color.toRgb565() != target_color.toRgb565()) {
                dvd_color = utils.lerpColor(dvd_color, target_color, decay);
                tex_dirty = true;
            }

            // DVD 弹跳（仅位置）
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
                hal.GPIO_WriteBit(
                    hal.GPIOA,
                    hal.GPIO_Pin_3,
                    if (led_on) hal.Bit_SET else hal.Bit_RESET,
                );

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
                // list.select(3);
            }

            // 应用新坐标，投影+包围盒+脏区域，然后渲染
            dvd_node.setPos(new_x, new_y);
            list.update();
            renderer.updateDirty(&cube_vertices, &pv);
            display.render();
        }
    }
}
