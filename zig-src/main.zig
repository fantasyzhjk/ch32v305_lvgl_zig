const std = @import("std");
const ch32 = @import("ch32.zig");
const hal = ch32.hal;
const c = ch32.c;
const lcd = @import("lcd.zig");
const debug = @import("debug.zig");
const ui = @import("ui.zig");
const interrupt = @import("interrupt.zig");
const usb = @import("usb.zig");
const tick = @import("tick.zig");
const color_mod = @import("color.zig");
const Color = color_mod.Color;

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

// DVD State
var dvd_dx: i32 = 3;
var dvd_dy: i32 = 2;
var dvd_color: Color = Color.BLUE;

// Title State
var title_x: i32 = 240;

fn drawTitle(node: *ui.Node, canvas: *ui.Canvas) void {
    const abs = node.getAbsArea();
    canvas.fillRect(abs.x, abs.y, abs.w, abs.h, Color.WHITE);

    var buf: [64]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "Zig Tree UI & DVD Demo @ {}", .{@as(*volatile u32, &lcd.dma_tc_counter).*}) catch "Zig Tree UI & DVD Demo";
    canvas.showString(abs.x + title_x, abs.y + 2, 16, s, Color.BLACK, Color.WHITE);
}

fn drawDvd(node: *ui.Node, canvas: *ui.Canvas) void {
    const abs = node.getAbsArea();

    canvas.fillRect(abs.x, abs.y, abs.w, abs.h, dvd_color);
    canvas.drawRect(abs.x, abs.y, abs.w, abs.h, Color.WHITE);

    // Some decorations
    canvas.drawLine(abs.x, abs.y, abs.x + abs.w - 1, abs.y + abs.h - 1, Color.YELLOW);
    canvas.drawCircle(abs.x + @divTrunc(abs.w, 2), abs.y + @divTrunc(abs.h, 2), @divTrunc(abs.h, 3), Color.GREEN);

    canvas.showString(abs.x + 14, abs.y + 8, 16, "DVD", Color.WHITE, null);
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

    // Initialize UI Display with dynamic draw_buf (24 lines height)
    var display = ui.Display.init(allocator, 24) catch unreachable;
    display.bind();

    // Allocate and Add Nodes using new API
    var title_node = display.createNode(0, 0, 240, 20, drawTitle) catch unreachable;
    var dvd_node = display.createNode(40, 50, 60, 30, drawDvd) catch unreachable;

    display.screenAddChild(title_node);
    display.screenAddChild(dvd_node);

    // Initial clear
    lcd.fill(0, 0, lcd.WIDTH, lcd.HEIGHT, Color.BLACK.toRgb565());

    var led_on = false;
    var last_frame: u32 = 0;

    while (true) {
        usb.task();

        const now = tick.millis();
        if (now -% last_frame >= 16) {
            last_frame = now;

            // Update Title
            title_x -= 2;
            if (title_x < -300) title_x = 240;
            title_node.invalidate();

            // Update DVD
            var new_x = dvd_node.area.x + dvd_dx;
            var new_y = dvd_node.area.y + dvd_dy;

            const min_y = title_node.area.h;
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
            }

            dvd_node.setPos(new_x, new_y);

            // Render UI
            display.render();
        }
    }
}
