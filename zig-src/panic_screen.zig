const std = @import("std");
const lcd = @import("lcd.zig");
const Canvas = @import("ui/canvas.zig").Canvas;
const Color = @import("ui/color.zig").Color565;
const types = @import("ui/types.zig");

const font_size: types.FontSize = .px12;
const metrics = types.fontMetrics(font_size);
const max_cols: usize = @divTrunc(@as(usize, lcd.WIDTH), @as(usize, @intCast(metrics.w)));
const max_rows: usize = @divTrunc(@as(usize, lcd.HEIGHT), @as(usize, @intCast(metrics.h)));
const line_pixels: usize = @as(usize, lcd.WIDTH) * @as(usize, @intCast(metrics.h));
const title_size: types.FontSize = .px24;
const title_metrics = types.fontMetrics(title_size);
const blue_screen_bg = Color.fromRgb(0x00, 0x78, 0xD7);
const max_backtrace_entries = 5;

var line_buf: [line_pixels]u16 = undefined;
var active: bool = false;

extern var _stext: u8;
extern var _ecode: u8;
extern var _sbacktrace: u8;
extern var _susrstack: u8;
extern var _eusrstack: u8;

fn drawTextLine(y: i32, text: []const u8, text_size: types.FontSize, fg: Color, bg: Color) void {
    if (y < 0 or y + metrics.h > lcd.HEIGHT) return;
    var canvas = Canvas.init(
        types.Rect.init(0, y, lcd.WIDTH, metrics.h),
        line_buf[0..],
    );

    canvas.fillRect(0, y, lcd.WIDTH, metrics.h, bg);
    canvas.showString(0, y, text_size, text, fg, bg);
    lcd.flushPixelsBlocking(
        0,
        @intCast(y),
        lcd.WIDTH - 1,
        @intCast(y + metrics.h - 1),
        line_buf[0..].ptr,
    );
}

fn drawLine(row: usize, text: []const u8, fg: Color, bg: Color) void {
    if (row >= max_rows) return;
    drawTextLine(@as(i32, @intCast(row)) * metrics.h, text, font_size, fg, bg);
}

fn drawEllipsisLine(y: i32, text: []const u8, fg: Color, bg: Color) void {
    var buf: [max_cols]u8 = undefined;
    const n = if (max_cols > 3) @min(text.len, max_cols - 3) else 0;
    @memcpy(buf[0..n], text[0..n]);
    @memcpy(buf[n .. n + 3], "...");
    drawTextLine(y, buf[0 .. n + 3], font_size, fg, bg);
}

fn drawTitle(y: i32, text: []const u8, fg: Color, bg: Color) void {
    var line: i32 = 0;
    while (line < title_metrics.h) : (line += metrics.h) {
        const curr_y = y + line;
        var canvas = Canvas.init(
            types.Rect.init(0, curr_y, lcd.WIDTH, metrics.h),
            line_buf[0..],
        );

        canvas.fillRect(0, curr_y, lcd.WIDTH, metrics.h, bg);
        canvas.showString(0, y, title_size, text, fg, bg);
        lcd.flushPixelsBlocking(
            0,
            @intCast(curr_y),
            lcd.WIDTH - 1,
            @intCast(curr_y + metrics.h - 1),
            line_buf[0..].ptr,
        );
    }
}

fn drawWrappedTextBounded(first_y: i32, max_y: i32, text: []const u8, fg: Color, bg: Color) i32 {
    var y = first_y;
    var index: usize = 0;
    var last_start: usize = 0;
    var last_end: usize = 0;

    while (index < text.len and y + metrics.h <= max_y) {
        if (text[index] == '\r') {
            index += 1;
            continue;
        }

        if (text[index] == '\n') {
            drawTextLine(y, "", font_size, fg, bg);
            y += metrics.h;
            index += 1;
            continue;
        }

        const start = index;
        var cols: usize = 0;
        while (index < text.len and cols < max_cols and text[index] != '\n' and text[index] != '\r') {
            index += 1;
            cols += 1;
        }

        last_start = start;
        last_end = index;
        drawTextLine(y, text[start..index], font_size, fg, bg);
        y += metrics.h;
    }

    if (index < text.len and y > first_y) {
        drawEllipsisLine(y - metrics.h, text[last_start..last_end], fg, bg);
    }

    return y;
}

fn drawWrappedText(first_y: i32, text: []const u8, fg: Color, bg: Color) i32 {
    return drawWrappedTextBounded(first_y, lcd.HEIGHT, text, fg, bg);
}

fn wrappedLineCount(text: []const u8) i32 {
    var lines: i32 = 0;
    var index: usize = 0;
    while (index < text.len) {
        if (text[index] == '\r') {
            index += 1;
        } else if (text[index] == '\n') {
            lines += 1;
            index += 1;
        } else {
            var cols: usize = 0;
            while (index < text.len and cols < max_cols and text[index] != '\n' and text[index] != '\r') {
                index += 1;
                cols += 1;
            }
            lines += 1;
        }
    }
    return lines;
}

fn stackPointer() usize {
    return asm volatile ("mv %[ret], sp"
        : [ret] "=r" (-> usize),
    );
}

fn isTextAddress(address: usize) bool {
    const text_start = @intFromPtr(&_stext);
    const text_end = @intFromPtr(&_ecode);
    return address >= text_start and address < text_end and (address & 0x1) == 0;
}

fn isBacktraceAddress(address: usize) bool {
    return address >= @intFromPtr(&_sbacktrace);
}

fn read16(address: usize) u16 {
    return @as(*const u16, @ptrFromInt(address)).*;
}

fn read32(address: usize) u32 {
    return @as(u32, read16(address)) | (@as(u32, read16(address + 2)) << 16);
}

fn isRaCall32(inst: u32) bool {
    const opcode = inst & 0x7f;
    const rd = (inst >> 7) & 0x1f;
    return rd == 1 and (opcode == 0x6f or opcode == 0x67);
}

fn isRaCall16(inst: u16) bool {
    const c_jal = (inst & 0xe003) == 0x2001;
    const c_jalr = (inst & 0xf07f) == 0x9002 and ((inst >> 7) & 0x1f) != 0;
    return c_jal or c_jalr;
}

fn callSiteFromReturnAddress(address: usize) ?usize {
    if (!isTextAddress(address)) return null;

    if (address >= @intFromPtr(&_stext) + 4) {
        const call_site = address - 4;
        const lo = read16(call_site);
        if ((lo & 0x3) == 0x3 and isRaCall32(read32(call_site))) return call_site;
    }

    if (address >= @intFromPtr(&_stext) + 2) {
        const call_site = address - 2;
        const inst = read16(call_site);
        if ((inst & 0x3) != 0x3 and isRaCall16(inst)) return call_site;
    }

    return null;
}

fn appendUnique(addrs: *[max_backtrace_entries]usize, count: *usize, return_address: usize) void {
    const address = callSiteFromReturnAddress(return_address) orelse return;
    if (!isBacktraceAddress(address)) return;

    var i: usize = 0;
    while (i < count.*) : (i += 1) {
        if (addrs[i] == address) return;
    }

    if (count.* < addrs.len) {
        addrs[count.*] = address;
        count.* += 1;
    }
}

fn collectBacktrace(first_address: ?usize, addrs: *[max_backtrace_entries]usize) usize {
    var count: usize = 0;
    if (first_address) |address| appendUnique(addrs, &count, address);

    const stack_start = @intFromPtr(&_susrstack);
    const stack_end = @intFromPtr(&_eusrstack);
    const sp = stackPointer();

    var scan = if (sp > stack_start and sp < stack_end) sp else stack_start;
    scan = std.mem.alignForward(usize, scan, @alignOf(usize));

    while (scan + @sizeOf(usize) <= stack_end and count < addrs.len) : (scan += @sizeOf(usize)) {
        const candidate = @as(*const usize, @ptrFromInt(scan)).*;
        appendUnique(addrs, &count, candidate);
    }

    return count;
}

fn drawBacktrace(first_y: i32, first_address: ?usize, fg: Color, bg: Color) void {
    var addrs: [max_backtrace_entries]usize = undefined;
    const count = collectBacktrace(first_address, &addrs);

    var y = drawWrappedText(first_y, "Backtrace:", fg, bg);
    if (count == 0) {
        _ = drawWrappedText(y, "no addresses captured", fg, bg);
        return;
    }

    var i: usize = 0;
    while (i < count and y + metrics.h <= lcd.HEIGHT) : (i += 1) {
        var line: [32]u8 = undefined;
        const text = std.fmt.bufPrint(&line, "#{d}: 0x{x}", .{ i, addrs[i] }) catch "#?: <format failed>";
        drawTextLine(y, text, font_size, fg, bg);
        y += metrics.h;
    }
}

pub fn show(message: []const u8, return_address: ?usize) void {
    if (@as(*volatile bool, &active).*) return;
    @as(*volatile bool, &active).* = true;

    if (!lcd.isInitialized()) return;

    const bg = blue_screen_bg;
    lcd.fillBlocking(0, 0, lcd.WIDTH, lcd.HEIGHT, bg.toRgb565());

    drawTitle(8, ":( KERNEL PANIC", Color.WHITE, bg);

    const primary_text = "An error occurred and the system must be halted.";
    const retry_text = "If this is the first time you have seen this screen, please reset the board and try again. If the problem continues, record the halt reason below.";
    const content_y: i32 = 44;
    const screen_lines = @divTrunc(@as(i32, lcd.HEIGHT) - content_y, metrics.h);
    const reason_lines = 1 + wrappedLineCount(message);

    var y: i32 = content_y;
    if (wrappedLineCount(primary_text) + 1 + reason_lines <= screen_lines) {
        y = drawWrappedText(y, primary_text, Color.WHITE, bg);
        y += metrics.h;
    }

    const used_lines = @divTrunc(y - content_y, metrics.h);
    if (used_lines + wrappedLineCount(retry_text) + 1 + reason_lines <= screen_lines) {
        y = drawWrappedText(y, retry_text, Color.WHITE, bg);
        y += metrics.h;
    }

    y = drawWrappedTextBounded(y, lcd.HEIGHT, "Halt Reason:", Color.WHITE, bg);
    y = drawWrappedTextBounded(y, lcd.HEIGHT, message, Color.WHITE, bg);

    if (y + metrics.h <= lcd.HEIGHT) {
        y += metrics.h;
        drawBacktrace(y, return_address, Color.WHITE, bg);
    }
}
