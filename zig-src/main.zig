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
    lcd.init();
    usb.init() catch |err| {
        debug.print("USB init failed: {}\r\n", .{err});
    };

    debug.print("hello from zig DVD tree-ui animation\r\n", .{});

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
        .area = ui.rect(40, 50, 60, 30),
    }) catch unreachable;
    const dvd_node = dvd_group.asNode();

    const dvd_panel = display.add(dvd_group, ui.Panel, .{
        .area = ui.rect(0, 0, 60, 30),
        .bg_color = dvd_color,
        .border_color = Color.WHITE,
    }) catch unreachable;

    _ = display.add(dvd_group, ui.Line, .{
        .area = ui.rect(0, 0, 60, 30),
        .color = Color.YELLOW,
    }) catch unreachable;

    _ = display.add(dvd_group, ui.Line, .{
        .area = ui.rect(0, 0, 60, 30),
        .color = Color.GREEN,
        .x1 = 59,
        .x2 = 0,
        .y2 = 29,
    }) catch unreachable;

    _ = display.add(dvd_group, ui.Label, .{
        .area = ui.rect(0, 7, 60, 16),
        .text = "DVD",
        .text_align = .center,
        .color = Color.WHITE,
    }) catch unreachable;

    // 清屏
    lcd.fill(0, 0, lcd.WIDTH, lcd.HEIGHT, Color.BLACK.toRgb565());

    var led_on = false;
    var last_frame: u32 = 0;

    while (true) {
        usb.task();

        const now = tick.millis();
        if (now -% last_frame >= 16) {
            last_frame = now;

            title.setText(formatTitleText());
            title.step(-2);

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

                dvd_panel.setBgColor(dvd_color);
                debug.print("DVD hit! New direction: ({}, {}), Color: {}\r\n", .{ dvd_dx, dvd_dy, dvd_color });
            }

            // 应用新坐标并渲染
            dvd_node.setPos(new_x, new_y);
            display.render();
        }
    }
}
