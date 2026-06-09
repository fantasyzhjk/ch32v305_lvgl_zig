const std = @import("std");
const usb = @import("usb.zig");

// extern fn _write(fd: c_int, buf: [*]u8, size: c_int) c_int;

pub fn allocPrint(
    gpa: std.mem.Allocator,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const msg = try std.fmt.allocPrint(
        gpa,
        fmt,
        args,
    );

    usb.write(msg);

    // _ = _write(
    //     1,
    //     @constCast(msg.ptr),
    //     @intCast(msg.len),
    // );
}

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
}

pub fn comptimePrint(
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const msg = std.fmt.comptimePrint(
        fmt,
        args,
    );

    usb.write(msg);
}
