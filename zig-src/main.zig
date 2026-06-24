const platform = @import("platform.zig");
const ch32 = @import("ch32.zig");
const debug = @import("debug.zig");
const tick = @import("tick.zig");
const lcd = @import("lcd.zig");
const usb = @import("usb.zig");
const app = @import("app.zig");

fn mainImpl() callconv(.c) if (platform.is_embedded) noreturn else void {
    if (comptime platform.is_embedded) {
        ch32.init();
        tick.init();
        usb.init() catch |err| {
            debug.print("USB init failed: {}\r\n", .{err});
        };
        lcd.init();
        debug.print("hello from zig DVD tree-ui animation\r\n", .{});
        debug.print("USB rotation control: send Y<yaw>,P<pitch>\\n\r\n", .{});
    } else {
        lcd.init();
        defer lcd.deinit();
        debug.print("LCD Simulator started. Close window to exit.\n", .{});
        app.run();
        return;
    }

    app.run();
    while (true) {}
}

// 嵌入式：导出 main 符号给启动汇编调用
comptime {
    if (platform.is_embedded) {
        @export(&mainImpl, .{ .name = "main", .linkage = .strong });
    }
}

// 仿真：Zig 启动代码需要的 pub fn main
pub fn main() void {
    mainImpl();
}
