pub const hal = @cImport({
    @cInclude("ch32v30x.h");
});

pub extern fn Delay_Init() void;
pub extern fn Delay_Us(n: u32) void;
pub extern fn Delay_Ms(n: u32) void;
