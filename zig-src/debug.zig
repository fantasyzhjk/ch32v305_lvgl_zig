const std = @import("std");
const usb = @import("usb.zig");

pub fn allocPrint(
    gpa: std.mem.Allocator,
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const msg = try std.fmt.allocPrint(gpa, fmt, args);
    usb.write(msg);
}

pub fn print(
    comptime fmt: []const u8,
    args: anytype,
) void {
    var buffer: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buffer, fmt, args) catch return;
    usb.write(msg);
}

pub fn comptimePrint(
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const msg = std.fmt.comptimePrint(fmt, args);
    usb.write(msg);
}
