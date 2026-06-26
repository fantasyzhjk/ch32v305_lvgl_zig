const std = @import("std");
const ch32 = @import("ch32.zig");
const hal = ch32.hal;
const debug = @import("debug.zig");
const tick = @import("tick.zig");
const lcd = @import("lcd.zig");
const event = @import("event.zig");
const ui = @import("ui/ui.zig");
const shader = ui.shader;
const utils = @import("utils.zig");
const Color = ui.Color565;
const Renderer3D = ui.Renderer3D;

var ui_pool: [20 * 1024]u8 = undefined;
var fba = std.heap.FixedBufferAllocator.init(&ui_pool);

var dvd_dx: i32 = 3;
var dvd_dy: i32 = 2;
var dvd_color: Color = Color.BLUE;
var target_color: Color = Color.BLUE;

var target_yaw: f32 = 0;
var target_pitch: f32 = 0;
const decay: f32 = 0.10;

const m = ui.FontSize.px12.metrics();
const tex_w: i32 = @as(i32, @intCast(3)) * m.w;
const tex_h: i32 = m.h;
var tex_buf: [18 * 12]u16 = undefined;
var tex_dirty: bool = true;

const tw_f: f32 = @floatFromInt(tex_w);
const th_f: f32 = @floatFromInt(tex_h);

const cube_vertices = utils.createCubeVertices(20);
const cube_edges = utils.autoGenEdges(&cube_vertices, 20.5);

fn updateTexture(r: *Renderer3D) void {
    if (!tex_dirty) return;
    @memset(&tex_buf, 0x07E0);
    r.compositeText(&tex_buf, @intCast(tex_w), 0, 0, "DVD", .px12, dvd_color);
    tex_dirty = false;
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

    var display = ui.Display.init(gpa, 20) catch |err| {
        @panic(@errorName(err));
    };
    display.bind();
    display.post_render = shader.gameBoyPostRender;

    const title = display.addToScreen(ui.widgets.MarqueeLabel, .{
        .area = ui.rect(0, 0, lcd.WIDTH, 20),
        .text = formatTitleText(gpa),
        .bg_color = Color.WHITE,
        .color = Color.BLACK,
        .gap = 24,
        .offset = lcd.WIDTH,
    }) catch unreachable;

    const tex_desc = ui.Texture{
        .pixels = &tex_buf,
        .w = tex_w,
        .h = tex_h,
        .stride = tex_w,
        .color_key = 0x07E0,
    };

    var cube_faces = [_]ui.Face{
        .{ .verts = .{ 4, 5, 7 }, .uvs = .{ .{ tw_f, 0 }, .{ 0, 0 }, .{ tw_f, th_f } }, .tex = tex_desc },
        .{ .verts = .{ 5, 6, 7 }, .uvs = .{ .{ 0, 0 }, .{ 0, th_f }, .{ tw_f, th_f } }, .tex = tex_desc },
    };

    var cube_mesh = ui.Mesh{
        .vertices = &cube_vertices,
        .edges = cube_edges,
        .faces = &cube_faces,
    };

    var models = [_]ui.Model3D{
        .{
            .mesh = &cube_mesh,
            .transform = .{ .position = .{ .x = -8, .y = 0, .z = 0 } },
            .edge_color = dvd_color,
        },
        .{
            .mesh = &cube_mesh,
            .transform = .{
                .position = .{ .x = 10, .y = 0, .z = 2 },
                .rotation_deg = .{ .x = 25, .y = 35, .z = 10 },
                .scale = .{ .x = 0.65, .y = 0.65, .z = 0.65 },
            },
            .edge_color = Color.GOLD,
        },
    };
    var scene = ui.Scene3D.init(gpa, &models) catch unreachable;
    defer scene.deinit();

    var renderer = display.addToScreen(ui.Renderer3D, .{
        .area = ui.rect(70, 70, 120, 120),
        .scene = &scene,
    }) catch unreachable;
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
        const dt_ms = now -% last_frame;
        if (dt_ms >= 16) {
            last_frame = now;

            title.setText(formatTitleText(gpa));
            title.step(-2);

            // 输入仍然旋转整个世界，不改变相机姿态。X 轴取反以保持原有屏幕俯仰方向。
            scene.world_transform.rotation_deg.y = utils.lerp(f32, scene.world_transform.rotation_deg.y, target_yaw, decay);
            scene.world_transform.rotation_deg.x = utils.lerp(f32, scene.world_transform.rotation_deg.x, -target_pitch, decay);

            if (dvd_color.toRgb565() != target_color.toRgb565()) {
                dvd_color = utils.lerpColor(dvd_color, target_color, decay);
                models[0].edge_color = dvd_color;
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
            updateTexture(renderer);
            list.update();
            renderer.update();
            display.render();
        }
    }
}
