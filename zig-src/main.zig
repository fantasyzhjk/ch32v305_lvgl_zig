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

    const title = display.create(ui.widgets.MarqueeLabel, .{ 0, 0, lcd.WIDTH, 20, formatTitleText() }) catch unreachable;
    title.setBgColor(Color.WHITE);
    title.setColor(Color.BLACK);
    title.gap = 24;
    title.setOffset(lcd.WIDTH);

    const dvd_group = display.create(ui.widgets.Container, .{ 40, 50, 60, 30 }) catch unreachable;
    const dvd_node = dvd_group.asNode();

    const dvd_panel = display.create(ui.widgets.Panel, .{ 0, 0, 60, 30 }) catch unreachable;
    dvd_panel.setBgColor(dvd_color);
    dvd_panel.setBorderColor(Color.WHITE);

    const dvd_line_a = display.create(ui.widgets.Line, .{ 0, 0, 60, 30, Color.YELLOW }) catch unreachable;
    const dvd_line_b = display.create(ui.widgets.Line, .{ 0, 0, 60, 30, Color.GREEN }) catch unreachable;
    dvd_line_b.setPoints(59, 0, 0, 29);

    const dvd_label = display.create(ui.widgets.Label, .{ 0, 7, 60, 16, "DVD" }) catch unreachable;
    dvd_label.text_align = .center;
    dvd_label.setColor(Color.WHITE);

    dvd_node.addChild(dvd_panel.asNode());
    dvd_node.addChild(dvd_line_a.asNode());
    dvd_node.addChild(dvd_line_b.asNode());
    dvd_node.addChild(dvd_label.asNode());

    display.screenAddChild(title.asNode());
    display.screenAddChild(dvd_node);

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
                hal.GPIO_WriteBit(hal.GPIOA, hal.GPIO_Pin_3, if (led_on) hal.Bit_SET else hal.Bit_RESET);

                dvd_color = if (dvd_dx > 0 and dvd_dy > 0) Color.BLUE else if (dvd_dx < 0 and dvd_dy > 0) Color.RED else if (dvd_dx > 0 and dvd_dy < 0) Color.MAGENTA else Color.CYAN;
                dvd_panel.setBgColor(dvd_color);
                debug.print("DVD hit! New direction: ({}, {}), Color: {}\r\n", .{ dvd_dx, dvd_dy, dvd_color });
            }

            dvd_node.setPos(new_x, new_y);

            display.render();
        }
    }
}
