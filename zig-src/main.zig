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
const Color = ui.Color565;

fn initLedPin() void {
    var gpio: hal.GPIO_InitTypeDef = .{
        .GPIO_Pin = 0,
        .GPIO_Speed = 0,
        .GPIO_Mode = 0,
    };

    hal.RCC_APB2PeriphClockCmd(hal.RCC_APB2Periph_GPIOA, hal.ENABLE);

    gpio.GPIO_Pin = hal.GPIO_Pin_3;
    gpio.GPIO_Speed = hal.GPIO_Speed_50MHz;
    gpio.GPIO_Mode = hal.GPIO_Mode_Out_PP;
    hal.GPIO_Init(hal.GPIOA, &gpio);
}

// Global memory pool for ALL UI objects (Display, DrawBuf, Nodes)
// Increased pool size to accommodate the draw buffer (~12KB) + nodes
var ui_pool: [16 * 1024]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&ui_pool);

var dvd_dx: i32 = 3;
var dvd_dy: i32 = 2;
var dvd_color: Color = Color.BLUE;

var title_text_buf: [64]u8 = undefined;

// USB 命令行缓冲区
var cmd_buf: [128]u8 = undefined;
var cmd_len: u32 = 0;

const Point3D = struct {
    x: f32,
    y: f32,
    z: f32,
};

const Point2D = struct {
    x: i32,
    y: i32,
};

pub fn createCubeVertices(comptime size: f32) [8]Point3D {
    const half = size / 2.0;
    return [8]Point3D{
        .{ .x = -half, .y = -half, .z = -half },
        .{ .x = half, .y = -half, .z = -half },
        .{ .x = half, .y = half, .z = -half },
        .{ .x = -half, .y = half, .z = -half },
        .{ .x = -half, .y = -half, .z = half },
        .{ .x = half, .y = -half, .z = half },
        .{ .x = half, .y = half, .z = half },
        .{ .x = -half, .y = half, .z = half },
    };
}

pub fn autoGenEdges(comptime vertices: []const Point3D, comptime max_dist: f32) []const Edge {
    // 1. 第一轮 comptime 循环：纯粹为了计算有多少条符合条件的边，用来开辟数组大小
    comptime var edge_count: usize = 0;
    inline for (vertices, 0..) |v1, i| {
        // 使用切片 [i + 1 ..] 避免重复计算 A->B 和 B->A
        inline for (vertices[i + 1 ..], 0..) |v2, j| {
            _ = j;
            const dx = v1.x - v2.x;
            const dy = v1.y - v2.y;
            const dz = v1.z - v2.z;
            const dist = @sqrt(dx * dx + dy * dy + dz * dz);

            if (dist > 0.1 and dist <= max_dist) {
                edge_count += 1;
            }
        }
    }

    // 2. 第二轮 comptime 循环：正确填入边的数据
    comptime var edges: [edge_count]Edge = undefined;
    comptime var idx: usize = 0;

    inline for (vertices, 0..) |v1, i| {
        inline for (vertices[i + 1 ..], 0..) |v2, j| {
            // j 是切片后的相对索引，real_j 才是该顶点在原 vertices 数组中的真实全局索引
            const real_j = j + i + 1;

            const dx = v1.x - v2.x;
            const dy = v1.y - v2.y;
            const dz = v1.z - v2.z;
            const dist = @sqrt(dx * dx + dy * dy + dz * dz);

            if (dist > 0.1 and dist <= max_dist) {
                // 【在这里正确使用 real_j！】连结第 i 个点和真正的第 real_j 个点
                edges[idx] = .{ i, real_j };
                idx += 1;
            }
        }
    }

    const final_edges = edges;
    return &final_edges;
}

// 1. 正方体的 8 个顶点
const cube_vertices = createCubeVertices(20);

// 2. 正方体的 12 条边（每条边由两个顶点的索引组成）
const Edge = [2]usize;
const cube_edges = autoGenEdges(&cube_vertices, 20.5);

const CAMERA_DIST: f32 = 30.0;
const FOV: f32 = 60.0;
var yaw: f32 = 0; // 绕Y轴旋转（左右）
var pitch: f32 = 0; // 绕X轴旋转（上下）

fn drawBox(node: *ui.Node, canvas: *ui.Canvas) void {
    const abs = node.getAbsArea();

    const yaw_rad = yaw * (3.14159265 / 180.0);
    const pitch_rad = pitch * (3.14159265 / 180.0);
    const cos_y = @cos(yaw_rad);
    const sin_y = @sin(yaw_rad);
    const cos_p = @cos(pitch_rad);
    const sin_p = @sin(pitch_rad);
    const center_x = @divTrunc(node.area.w, 2);
    const center_y = @divTrunc(node.area.h, 2);
    var projected_points: [8]Point2D = undefined;
    for (cube_vertices, 0..) |vertex, i| {
        // 先绕 Y 轴旋转（yaw 左右）
        const rx = vertex.x * cos_y - vertex.z * sin_y;
        const ry = vertex.y;
        const rz = vertex.x * sin_y + vertex.z * cos_y;
        // 再绕 X 轴旋转（pitch 上下）
        const ry2 = ry * cos_p - rz * sin_p;
        const rz2 = ry * sin_p + rz * cos_p;

        // 平移 Z 轴防穿模/除以0
        const trans_z = rz2 + CAMERA_DIST;

        // 透视投影转换为屏幕 2D 坐标
        projected_points[i] = Point2D{
            .x = @as(i32, @intFromFloat((rx * FOV) / trans_z)) + center_x,
            .y = @as(i32, @intFromFloat((ry2 * FOV) / trans_z)) + center_y,
        };
    }

    for (cube_edges) |edge| {
        const p1 = projected_points[edge[0]];
        const p2 = projected_points[edge[1]];
        const p1x = p1.x + abs.x;
        const p1y = p1.y + abs.y;
        const p2x = p2.x + abs.x;
        const p2y = p2.y + abs.y;

        canvas.drawLine(p1x, p1y, p2x, p2y, dvd_color);
    }

    // 在前表面（顶点4-7）画 3D 透视文字
    const quad = [4]ui.types.Point{
        .{ .x = projected_points[4].x + abs.x, .y = projected_points[4].y + abs.y },
        .{ .x = projected_points[5].x + abs.x, .y = projected_points[5].y + abs.y },
        .{ .x = projected_points[6].x + abs.x, .y = projected_points[6].y + abs.y },
        .{ .x = projected_points[7].x + abs.x, .y = projected_points[7].y + abs.y },
    };
    canvas.drawTextOnQuad(quad, "DVD", .px12, dvd_color);
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
    var new_yaw = yaw;
    var new_pitch = pitch;

    // 跳过前导空白
    while (pos < line.len and line[pos] == ' ') pos += 1;

    while (pos < line.len) {
        if (line[pos] == 'Y' or line[pos] == 'y') {
            pos += 1;
            if (parseFloat(line[pos..])) |r| {
                new_yaw = r.value;
                pos += r.consumed;
            }
        } else if (line[pos] == 'P' or line[pos] == 'p') {
            pos += 1;
            if (parseFloat(line[pos..])) |r| {
                new_pitch = r.value;
                pos += r.consumed;
            }
        } else if (line[pos] == ',') {
            pos += 1;
        } else {
            break;
        }
    }

    yaw = new_yaw;
    pitch = new_pitch;
    // 标记 cube 节点需要重绘（由主循环中的 invalidate 或 render 驱动）
    debug.print("rot yaw={d} pitch={d}\r\n", .{ yaw, pitch });
}

fn formatTitleText() []const u8 {
    return std.fmt.bufPrint(
        &title_text_buf,
        "Zig Tree UI & DVD Demo @ {}",
        .{@as(*volatile u32, &lcd.dma_tc_counter).*},
    ) catch "Zig Tree UI & DVD Demo";
}

pub export fn main() noreturn {
    // 1. 硬件外设初始化
    hal.NVIC_PriorityGroupConfig(hal.NVIC_PriorityGroup_2);
    c.Delay_Init();
    c.USART_Printf_Init(115200);
    initLedPin();

    tick.init();
    usb.init() catch |err| {
        debug.print("USB init failed: {}\r\n", .{err});
    };
    lcd.init();

    debug.print("hello from zig DVD tree-ui animation\r\n", .{});
    debug.print("USB rotation control: send Y<yaw>,P<pitch>\\n\r\n", .{});

    const allocator = fba.allocator();
    var display = ui.Display.init(allocator, 24) catch unreachable;
    display.bind();

    const title = display.addToScreen(ui.MarqueeLabel, .{
        .area = ui.rect(0, 0, lcd.WIDTH, 20),
        .text = formatTitleText(),
        .bg_color = Color.WHITE,
        .color = Color.BLACK,
        .gap = 24,
        .offset = lcd.WIDTH,
    }) catch unreachable;

    const dvd_group = display.addToScreen(ui.Container, .{
        .area = ui.rect(40, 50, 100, 100),
    }) catch unreachable;
    const dvd_node = dvd_group.asNode();
    dvd_node.draw_cb = drawBox;

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
        if (got_cmd) {
            dvd_node.invalidate();
        }

        const now = tick.millis();
        if (now -% last_frame >= 16) {
            last_frame = now;

            title.setText(formatTitleText());
            title.step(-2);

            // DVD 弹跳驱动 3D 旋转
            const rot_speed: f32 = 1.5;
            yaw += @as(f32, @floatFromInt(dvd_dx)) * rot_speed;
            pitch += @as(f32, @floatFromInt(dvd_dy)) * rot_speed;

            var new_x = dvd_node.area.x + dvd_dx;
            var new_y = dvd_node.area.y + dvd_dy;

            const min_y = title.asNode().area.h;
            var hit = false;

            if (new_x <= 0) {
                new_x = 0;
                dvd_dx = -dvd_dx;
                hit = true;
            } else if (new_x + dvd_node.area.w >= lcd.WIDTH) {
                new_x = lcd.WIDTH - dvd_node.area.w;
                dvd_dx = -dvd_dx;
                hit = true;
            }

            if (new_y <= min_y) {
                new_y = min_y;
                dvd_dy = -dvd_dy;
                hit = true;
            } else if (new_y + dvd_node.area.h >= lcd.HEIGHT) {
                new_y = lcd.HEIGHT - dvd_node.area.h;
                dvd_dy = -dvd_dy;
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
                    dvd_color = Color.BLUE;
                } else if (dvd_dx < 0 and dvd_dy > 0) {
                    dvd_color = Color.RED;
                } else if (dvd_dx > 0 and dvd_dy < 0) {
                    dvd_color = Color.MAGENTA;
                } else {
                    dvd_color = Color.CYAN;
                }

                dvd_node.invalidate();
                debug.print("DVD hit! New direction: ({}, {}), Color: {}\r\n", .{ dvd_dx, dvd_dy, dvd_color });
            }

            // 应用新坐标并渲染
            dvd_node.setPos(new_x, new_y);
            display.render();
        }
    }
}
