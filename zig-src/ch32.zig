pub const hal = @cImport({
    @cInclude("ch32v30x.h");
    @cInclude("core_riscv.h");
    @cInclude("ch32v30x_it.h");
});

pub const c = @cImport({
    @cInclude("debug.h");
    @cInclude("nanoprintf.h");
    @cInclude("stdio.h");
});

fn initLedPin() void {
    var gpio: hal.GPIO_InitTypeDef = .{};

    hal.RCC_APB2PeriphClockCmd(hal.RCC_APB2Periph_GPIOA, hal.ENABLE);

    gpio.GPIO_Pin = hal.GPIO_Pin_3;
    gpio.GPIO_Speed = hal.GPIO_Speed_50MHz;
    gpio.GPIO_Mode = hal.GPIO_Mode_Out_PP;
    hal.GPIO_Init(hal.GPIOA, &gpio);
}

pub fn init() void {
    hal.NVIC_PriorityGroupConfig(hal.NVIC_PriorityGroup_2);
    c.Delay_Init();
    c.USART_Printf_Init(115200);
    hal.RCC_AHBPeriphClockCmd(hal.RCC_AHBPeriph_RNG, hal.ENABLE);
    hal.RNG_Cmd(hal.ENABLE);
    initLedPin();
}
