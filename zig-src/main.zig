const ch32 = @import("ch32.zig");
const hal = ch32.hal;
const c = ch32.c;
const lcd = @import("lcd.zig");
const debug = @import("debug.zig");

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

fn drawDemoGraphics() void {
    // 1. 清屏为黑色
    lcd.fill(0, 0, lcd.WIDTH, lcd.HEIGHT, lcd.Color.BLACK);
    c.Delay_Ms(100);

    // 2. 标题文字（不同字号）
    lcd.fore_color = lcd.Color.WHITE;
    lcd.back_color = lcd.Color.BLACK;
    lcd.showString(10, 5, 16, "Zig LCD Graphics Demo");

    lcd.fore_color = lcd.Color.GREEN;
    lcd.showString(10, 22, 12, "CH32V305 + SPI TFT 240x240");

    // 3. 彩色水平线（RGB）
    lcd.fore_color = lcd.Color.RED;
    lcd.drawLine(10, 38, 230, 38);
    lcd.fore_color = lcd.Color.GREEN;
    lcd.drawLine(10, 41, 230, 41);
    lcd.fore_color = lcd.Color.BLUE;
    lcd.drawLine(10, 44, 230, 44);

    // 4. 空心矩形 + 填充矩形
    lcd.fore_color = lcd.Color.YELLOW;
    lcd.drawRectangle(15, 55, 105, 115);
    lcd.fill(115, 55, 225, 115, lcd.Color.MAGENTA);

    // 5. 空心圆（不同颜色、不同半径）
    lcd.fore_color = lcd.Color.CYAN;
    lcd.drawCircle(60, 145, 28);
    lcd.fore_color = lcd.Color.ORANGE;
    lcd.drawCircle(180, 145, 22);

    // 6. 交叉斜线（形成三角形）
    lcd.fore_color = lcd.Color.PURPLE;
    lcd.drawLine(20, 200, 120, 110);
    lcd.fore_color = lcd.Color.GOLD;
    lcd.drawLine(220, 200, 120, 110);

    // 7. 点阵虚线
    lcd.fore_color = lcd.Color.WHITE;
    var i: u16 = 0;
    while (i < 40) : (i += 1) {
        lcd.drawPoint(90 + i * 2, 185);
    }

    // 8. 数字显示
    lcd.fore_color = lcd.Color.LGRAY;
    lcd.showNum(160, 185, 305, 3, 16);

    // 9. 底部说明文字
    lcd.fore_color = lcd.Color.SILVER;
    lcd.showString(10, 210, 24, "Hello from Zig!");
}

pub export fn main() noreturn {
    hal.NVIC_PriorityGroupConfig(hal.NVIC_PriorityGroup_2);
    c.Delay_Init();
    c.USART_Printf_Init(115200);
    initLedPin();

    lcd.init();

    debug.print("hello from zig\r\n", .{});

    // 绘制丰富的图形演示
    drawDemoGraphics();

    var counter: u32 = 0;
    var led_on = false;

    while (true) {
        counter += 1;
        if (counter >= 500) {
            counter = 0;
            led_on = !led_on;
            hal.GPIO_WriteBit(hal.GPIOA, hal.GPIO_Pin_3, if (led_on) hal.Bit_SET else hal.Bit_RESET);
        }

        c.Delay_Ms(1);
    }
}
