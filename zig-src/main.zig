const ch32 = @import("ch32.zig");
const c = ch32.c;

fn initLedPin() void {
    var gpio: c.GPIO_InitTypeDef = .{
        .GPIO_Pin = 0,
        .GPIO_Speed = 0,
        .GPIO_Mode = 0,
    };

    c.RCC_APB2PeriphClockCmd(c.RCC_APB2Periph_GPIOA, c.ENABLE);

    gpio.GPIO_Pin = c.GPIO_Pin_3;
    gpio.GPIO_Speed = c.GPIO_Speed_50MHz;
    gpio.GPIO_Mode = c.GPIO_Mode_Out_PP;
    c.GPIO_Init(c.GPIOA, &gpio);
}

pub export fn main() noreturn {
    c.NVIC_PriorityGroupConfig(c.NVIC_PriorityGroup_2);
    ch32.Delay_Init();
    initLedPin();

    var led_on = false;
    while (true) {
        led_on = !led_on;
        c.GPIO_WriteBit(c.GPIOA, c.GPIO_Pin_3, if (led_on) c.Bit_SET else c.Bit_RESET);
        ch32.Delay_Ms(50);
    }
}
