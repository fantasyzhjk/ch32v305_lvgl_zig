pub const c = @cImport({
    @cInclude("ch32v30x.h");
    @cInclude("ch32v30x_gpio.h");
    @cInclude("ch32v30x_misc.h");
    @cInclude("ch32v30x_rcc.h");
});

pub extern fn Delay_Init() void;
pub extern fn Delay_Us(n: u32) void;
pub extern fn Delay_Ms(n: u32) void;
