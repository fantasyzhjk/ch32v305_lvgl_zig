const platform = @import("platform.zig");

pub const hal = if (platform.is_embedded)
    @cImport({
        @cInclude("ch32v30x.h");
        @cInclude("core_riscv.h");
        @cInclude("ch32v30x_it.h");
    })
else
    @import("sim/hal_stub.zig");

pub const c = if (platform.is_embedded)
    @cImport({
        @cInclude("debug.h");
        @cInclude("nanoprintf.h");
        @cInclude("stdio.h");
    })
else
    struct {
        pub const SystemCoreClock: u32 = 144_000_000;
        pub fn Delay_Init() void {}
        pub fn Delay_Ms(_: anytype) void {}
        pub fn USART_Printf_Init(_: anytype) void {}
    };

pub fn init() void {
    if (platform.is_embedded) {
        hal.NVIC_PriorityGroupConfig(hal.NVIC_PriorityGroup_2);
        c.Delay_Init();
        c.USART_Printf_Init(115200);
        hal.RCC_AHBPeriphClockCmd(hal.RCC_AHBPeriph_RNG, hal.ENABLE);
        hal.RNG_Cmd(hal.ENABLE);

        var gpio: hal.GPIO_InitTypeDef = .{};
        hal.RCC_APB2PeriphClockCmd(hal.RCC_APB2Periph_GPIOA, hal.ENABLE);
        gpio.GPIO_Pin = hal.GPIO_Pin_3;
        gpio.GPIO_Speed = hal.GPIO_Speed_50MHz;
        gpio.GPIO_Mode = hal.GPIO_Mode_Out_PP;
        hal.GPIO_Init(hal.GPIOA, &gpio);
    }
}
