const interrupt = @import("../interrupt.zig");
const ch32 = @import("../ch32.zig");

const hal = ch32.hal;
const c = ch32.c;

extern fn usb_app_init() void;
extern fn usb_app_task() void;
extern fn usb_write(data: *const anyopaque, len: u32) void;
extern fn usb_available() u32;
extern fn usb_read(buf: *anyopaque, len: u32) u32;
extern fn dcd_int_handler(port: u8) void;

pub const Error = error{
    InvalidUsbFsClock,
};

comptime {
    interrupt.exportFastIrq("USBHS_IRQHandler", struct {
        fn impl() callconv(.c) void {
            dcd_int_handler(0);
        }
    }.impl);

    interrupt.exportFastIrq("OTG_FS_IRQHandler", struct {
        fn impl() callconv(.c) void {
            dcd_int_handler(0);
        }
    }.impl);
}

pub fn init() Error!void {
    try initClock();
    usb_app_init();
}

pub fn task() []const u8 {
    var buf: [64]u8 = undefined;

    const n = read(buf[0..]);

    usb_app_task();

    if (n != 0) {
        return buf[0..@intCast(n)];
    }
    return &.{};
}

pub fn write(data: []const u8) void {
    if (data.len == 0) return;

    usb_write(data.ptr, @intCast(data.len));
}

pub fn available() u32 {
    return usb_available();
}

pub fn read(buf: []u8) u32 {
    if (buf.len == 0) return 0;

    return usb_read(buf.ptr, @intCast(buf.len));
}

pub fn readByte() ?u8 {
    var b: u8 = undefined;

    if (read((&b)[0..1]) == 1) {
        return b;
    }

    return null;
}

fn initClock() Error!void {
    // USBHS
    hal.RCC_USBCLK48MConfig(hal.RCC_USBCLK48MCLKSource_USBPHY);
    hal.RCC_USBHSPLLCLKConfig(hal.RCC_HSBHSPLLCLKSource_HSE);
    hal.RCC_USBHSConfig(hal.RCC_USBPLL_Div2);
    hal.RCC_USBHSPLLCKREFCLKConfig(hal.RCC_USBHSPLLCKREFCLK_4M);
    hal.RCC_USBHSPHYPLLALIVEcmd(hal.ENABLE);
    hal.RCC_AHBPeriphClockCmd(hal.RCC_AHBPeriph_USBHS, hal.ENABLE);

    // OTG FS
    const otg_div = switch (c.SystemCoreClock) {
        48_000_000 => hal.RCC_OTGFSCLKSource_PLLCLK_Div1,
        96_000_000 => hal.RCC_OTGFSCLKSource_PLLCLK_Div2,
        144_000_000 => hal.RCC_OTGFSCLKSource_PLLCLK_Div3,
        else => return Error.InvalidUsbFsClock,
    };

    hal.RCC_OTGFSCLKConfig(otg_div);
    hal.RCC_AHBPeriphClockCmd(hal.RCC_AHBPeriph_OTG_FS, hal.ENABLE);
}
