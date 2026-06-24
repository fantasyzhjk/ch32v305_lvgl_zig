const interrupt = @import("../interrupt.zig");
const ch32 = @import("../ch32.zig");
const hal = ch32.hal;
const c = ch32.c;

pub var system_ticks: u32 = 0;

comptime {
    interrupt.exportFastIrq("TIM2_IRQHandler", struct {
        fn impl() callconv(.c) void {
            if (hal.TIM_GetITStatus(hal.TIM2, hal.TIM_IT_Update) != hal.RESET) {
                hal.TIM_ClearITPendingBit(hal.TIM2, hal.TIM_IT_Update);
                @as(*volatile u32, &system_ticks).* +%= 1;
            }
        }
    }.impl);
}

pub fn init() void {
    hal.RCC_APB1PeriphClockCmd(hal.RCC_APB1Periph_TIM2, hal.ENABLE);

    var tim: hal.TIM_TimeBaseInitTypeDef = undefined;
    tim.TIM_Prescaler = @intCast(c.SystemCoreClock / 1_000_000 - 1); // 1MHz
    tim.TIM_CounterMode = hal.TIM_CounterMode_Up;
    tim.TIM_Period = 1000 - 1; // 1ms
    tim.TIM_ClockDivision = hal.TIM_CKD_DIV1;
    tim.TIM_RepetitionCounter = 0;

    hal.TIM_TimeBaseInit(hal.TIM2, &tim);
    hal.TIM_ITConfig(hal.TIM2, hal.TIM_IT_Update, hal.ENABLE);

    hal.EnableInterrupts(hal.TIM2_IRQn);

    hal.TIM_Cmd(hal.TIM2, hal.ENABLE);
}

pub inline fn millis() u32 {
    return @as(*volatile u32, &system_ticks).*;
}
