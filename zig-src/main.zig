const std = @import("std");
const ch32 = @import("ch32.zig");
const hal = ch32.hal;
const c = ch32.c;
const lcd = @import("lcd.zig");
const debug = @import("debug.zig");
const ui = @import("ui.zig");

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

// 裸机环境堆内存配置 (20KB SRAM)
var heap_memory: [20 * 1024]u8 = undefined;

pub export fn main() noreturn {
    hal.NVIC_PriorityGroupConfig(hal.NVIC_PriorityGroup_2);
    c.Delay_Init();
    c.USART_Printf_Init(115200);
    initLedPin();

    lcd.init();

    debug.print("hello from zig DVD animation\r\n", .{});

    // 初始化动态内存分配器
    var fba = std.heap.FixedBufferAllocator.init(&heap_memory);
    const allocator = fba.allocator();

    // 背景清屏
    lcd.fill(0, 0, lcd.WIDTH, lcd.HEIGHT, lcd.Color.BLACK);
    c.Delay_Ms(100);

    // DVD 动画状态变量
    var old_x: i32 = 40;
    var old_y: i32 = 50;
    var new_x: i32 = 40;
    var new_y: i32 = 50;
    var dvd_dx: i32 = 3;
    var dvd_dy: i32 = 3;
    const dvd_w: u16 = 60;
    const dvd_h: u16 = 30;

    // 标题滚动状态变量
    var title_x: i32 = 240; // 从最右侧出现

    // DVD 运动区域边界
    const min_y: i32 = 20;

    var led_on = false;

    while (true) {
        // --- 1. 更新顶部滚动标题 ---
        title_x -= 2;
        if (title_x < -200) {
            title_x = 240; // 滚动到底重置
        }

        if (ui.Canvas.create(allocator, 0, 0, 240, 20)) |canvas_val| {
            var title_canvas = canvas_val;
            defer title_canvas.destroy(allocator);

            title_canvas.clear(lcd.Color.WHITE);
            const s = std.fmt.allocPrint(allocator, "Zig Zoned UI & DVD Demo @ {}", .{@as(*volatile i32, &lcd.dma_tc_flag).*}) catch "Zig Zoned UI & DVD Demo";
            defer allocator.free(s);
            title_canvas.showString(title_x, 2, 16, s, lcd.Color.BLACK, lcd.Color.WHITE);
            title_canvas.flush();
        } else |_| {
            debug.print("OOM: Failed to alloc title canvas\r\n", .{});
        }

        // --- 2. 更新 DVD 动画 ---
        new_x = old_x + dvd_dx;
        new_y = old_y + dvd_dy;

        // 边缘碰撞检测并反弹
        if (new_x <= 0) {
            new_x = 0;
            dvd_dx = -dvd_dx;
            led_on = !led_on;
        } else if (new_x + dvd_w >= lcd.WIDTH) {
            new_x = lcd.WIDTH - dvd_w;
            dvd_dx = -dvd_dx;
            led_on = !led_on;
        }

        if (new_y <= min_y) {
            new_y = min_y;
            dvd_dy = -dvd_dy;
            led_on = !led_on;
        } else if (new_y + dvd_h >= lcd.HEIGHT) {
            new_y = lcd.HEIGHT - dvd_h;
            dvd_dy = -dvd_dy;
            led_on = !led_on;
        }

        hal.GPIO_WriteBit(hal.GPIOA, hal.GPIO_Pin_3, if (led_on) hal.Bit_SET else hal.Bit_RESET);

        // 计算脏区域 (Dirty Region) 包含旧位置和新位置
        const old_rect = ui.Rect{ .x = @intCast(old_x), .y = @intCast(old_y), .w = dvd_w, .h = dvd_h };
        const new_rect = ui.Rect{ .x = @intCast(new_x), .y = @intCast(new_y), .w = dvd_w, .h = dvd_h };
        const dirty_rect = old_rect.unionRect(new_rect);

        // 动态分配脏区域大小的 Canvas
        if (ui.Canvas.create(allocator, dirty_rect.x, dirty_rect.y, dirty_rect.w, dirty_rect.h)) |canvas_val| {
            var dirty_canvas = canvas_val;
            defer dirty_canvas.destroy(allocator);

            // 1. 清理背景 (在内存中，无闪烁)
            dirty_canvas.clear(lcd.Color.BLACK);

            // 2. 绘制新的 DVD 图像 (计算在新 Canvas 中的相对坐标)
            const rel_x = @as(u16, @intCast(new_x)) - dirty_rect.x;
            const rel_y = @as(u16, @intCast(new_y)) - dirty_rect.y;

            const dvd_bg = if (dvd_dx > 0 and dvd_dy > 0) lcd.Color.BLUE else if (dvd_dx < 0 and dvd_dy > 0) lcd.Color.RED else if (dvd_dx > 0 and dvd_dy < 0) lcd.Color.MAGENTA else lcd.Color.CYAN;

            dirty_canvas.fillRect(rel_x, rel_y, dvd_w, dvd_h, dvd_bg);
            dirty_canvas.drawRect(rel_x, rel_y, dvd_w, dvd_h, lcd.Color.WHITE);
            // Demonstrate new primitives
            dirty_canvas.drawLine(rel_x, rel_y, rel_x + dvd_w - 1, rel_y + dvd_h - 1, lcd.Color.YELLOW);
            dirty_canvas.drawCircle(rel_x + dvd_w / 2, rel_y + dvd_h / 2, dvd_h / 3, lcd.Color.GREEN);

            dirty_canvas.showString(rel_x + 14, rel_y + 8, 16, "DVD", lcd.Color.WHITE, null);

            // 3. DMA 将完美的复合图像推送到屏幕的脏区域
            dirty_canvas.flush();
        } else |_| {
            debug.print("OOM: Failed to alloc dirty region\r\n", .{});
        }

        // 保存新位置作为下一次的旧位置
        old_x = new_x;
        old_y = new_y;

        c.Delay_Ms(15);
    }
}
