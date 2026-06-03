const ch32 = @import("ch32.zig");
const hal = ch32.hal;

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

pub export fn main() noreturn {
    hal.NVIC_PriorityGroupConfig(hal.NVIC_PriorityGroup_2);
    ch32.Delay_Init();
    initLedPin();

    var led_on = false;
    while (true) {
        led_on = !led_on;
        hal.GPIO_WriteBit(hal.GPIOA, hal.GPIO_Pin_3, if (led_on) hal.Bit_SET else hal.Bit_RESET);
        ch32.Delay_Ms(50);
    }
}
