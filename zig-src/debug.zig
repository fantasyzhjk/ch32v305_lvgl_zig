const std = @import("std");
const usb = @import("usb.zig");

// extern fn _write(fd: c_int, buf: [*]u8, size: c_int) c_int;

pub fn print(
    comptime fmt: []const u8,
    args: anytype,
) void {
    var buffer: [256]u8 = undefined;

    const msg = std.fmt.bufPrint(
        &buffer,
        fmt,
        args,
    ) catch return;

    usb.write(msg);

    // _ = _write(
    //     1,
    //     @constCast(msg.ptr),
    //     @intCast(msg.len),
    // );
}
