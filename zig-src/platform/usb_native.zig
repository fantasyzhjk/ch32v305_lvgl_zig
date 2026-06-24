//! USB stub for native simulation.
//! Non-blocking stdin read, platform-specific.
const std = @import("std");
const builtin = @import("builtin");
const native_os = builtin.os.tag;

pub fn init() !void {}

pub fn task() []const u8 {
    var buf: [64]u8 = undefined;
    const n = readStdinNonBlocking(&buf);
    return if (n > 0) buf[0..n] else &.{};
}

pub fn write(data: []const u8) void {
    std.debug.print("{s}", .{data});
}

pub fn available() u32 {
    return 0;
}

pub fn read(buf: []u8) u32 {
    return @intCast(readStdinNonBlocking(buf));
}

pub fn readByte() ?u8 {
    var b: [1]u8 = undefined;
    return if (readStdinNonBlocking(&b) == 1) b[0] else null;
}

fn readStdinNonBlocking(buf: []u8) usize {
    if (native_os == .windows) {
        return readStdinWindows(buf);
    } else {
        return readStdinPosix(buf);
    }
}

// ── Windows: PeekNamedPipe + ReadFile ──

const w = std.os.windows;

extern "kernel32" fn PeekNamedPipe(
    hNamedPipe: w.HANDLE,
    lpBuffer: ?*anyopaque,
    nBufferSize: w.DWORD,
    lpBytesRead: ?*w.DWORD,
    lpTotalBytesAvail: ?*w.DWORD,
    lpBytesLeftThisMessage: ?*w.DWORD,
) callconv(.c) w.BOOL;

extern "kernel32" fn ReadFile(
    hFile: w.HANDLE,
    lpBuffer: [*]u8,
    nNumberOfBytesToRead: w.DWORD,
    lpNumberOfBytesRead: ?*w.DWORD,
    lpOverlapped: ?*anyopaque,
) callconv(.c) w.BOOL;

fn readStdinWindows(buf: []u8) usize {
    const handle = w.peb().ProcessParameters.hStdInput;

    var avail: w.DWORD = 0;
    if (PeekNamedPipe(handle, null, 0, null, &avail, null) == .FALSE) return 0;
    if (avail == 0) return 0;

    const to_read: w.DWORD = @intCast(@min(avail, buf.len));
    var read_bytes: w.DWORD = 0;
    if (ReadFile(handle, buf.ptr, to_read, &read_bytes, null) == .FALSE) return 0;
    return @intCast(read_bytes);
}

// ── POSIX: poll + read ──

fn readStdinPosix(buf: []u8) usize {
    const c = std.c;
    var pfd = c.pollfd{ .fd = 0, .events = c.POLL.IN, .revents = 0 };
    if (c.poll(&pfd, 1, 0) <= 0) return 0;
    if ((pfd.revents & c.POLL.IN) == 0) return 0;
    const n = c.read(0, buf.ptr, buf.len);
    return if (n > 0) @intCast(n) else 0;
}
