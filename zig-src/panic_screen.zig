const std = @import("std");
const lcd = @import("lcd.zig");
const font = @import("ui/font.zig");
const Color = @import("ui/color.zig").Color565;
const FontSize = @import("ui/types.zig").FontSize;

const background = Color.fromRgb(0x00, 0x78, 0xD7).toRgb565();
const foreground = Color.WHITE.toRgb565();

const margin_x: i32 = 12;
const reason_y: i32 = 96;
const reason_cols: usize = 36;
const reason_rows: usize = 7;

var active: bool = false;

/// Zig 0.16 panic namespace. This intentionally mirrors std.debug.simple_panic
/// while routing every failure through the LCD panic screen.
pub const Panic = struct {
    pub const call = panicCall;

    pub fn sentinelMismatch(expected: anytype, found: @TypeOf(expected)) noreturn {
        _ = found;
        panicCall("sentinel mismatch", @returnAddress());
    }

    pub fn unwrapError(err: anyerror) noreturn {
        _ = &err;
        panicCall("attempt to unwrap error", @returnAddress());
    }

    pub fn outOfBounds(index: usize, len: usize) noreturn {
        _ = index;
        _ = len;
        panicCall("index out of bounds", @returnAddress());
    }

    pub fn startGreaterThanEnd(start: usize, end: usize) noreturn {
        _ = start;
        _ = end;
        panicCall("start index is larger than end index", @returnAddress());
    }

    pub fn inactiveUnionField(active_field: anytype, accessed: @TypeOf(active_field)) noreturn {
        _ = accessed;
        panicCall("access of inactive union field", @returnAddress());
    }

    pub fn sliceCastLenRemainder(src_len: usize) noreturn {
        _ = src_len;
        panicCall("slice length does not divide destination", @returnAddress());
    }

    pub fn reachedUnreachable() noreturn {
        panicCall("reached unreachable code", @returnAddress());
    }

    pub fn unwrapNull() noreturn {
        panicCall("attempt to use null value", @returnAddress());
    }

    pub fn castToNull() noreturn {
        panicCall("cast causes pointer to be null", @returnAddress());
    }

    pub fn incorrectAlignment() noreturn {
        panicCall("incorrect alignment", @returnAddress());
    }

    pub fn invalidErrorCode() noreturn {
        panicCall("invalid error code", @returnAddress());
    }

    pub fn integerOutOfBounds() noreturn {
        panicCall("integer does not fit in destination type", @returnAddress());
    }

    pub fn integerOverflow() noreturn {
        panicCall("integer overflow", @returnAddress());
    }

    pub fn shlOverflow() noreturn {
        panicCall("left shift overflowed bits", @returnAddress());
    }

    pub fn shrOverflow() noreturn {
        panicCall("right shift overflowed bits", @returnAddress());
    }

    pub fn divideByZero() noreturn {
        panicCall("division by zero", @returnAddress());
    }

    pub fn exactDivisionRemainder() noreturn {
        panicCall("exact division produced remainder", @returnAddress());
    }

    pub fn integerPartOutOfBounds() noreturn {
        panicCall("integer part of float is out of bounds", @returnAddress());
    }

    pub fn corruptSwitch() noreturn {
        panicCall("switch on corrupt value", @returnAddress());
    }

    pub fn shiftRhsTooBig() noreturn {
        panicCall("shift amount is greater than type size", @returnAddress());
    }

    pub fn invalidEnumValue() noreturn {
        panicCall("invalid enum value", @returnAddress());
    }

    pub fn forLenMismatch() noreturn {
        panicCall("for loop operands have different lengths", @returnAddress());
    }

    pub fn copyLenMismatch() noreturn {
        panicCall("source and destination lengths differ", @returnAddress());
    }

    pub fn memcpyAlias() noreturn {
        panicCall("@memcpy arguments alias", @returnAddress());
    }

    pub fn noreturnReturned() noreturn {
        panicCall("noreturn function returned", @returnAddress());
    }
};

noinline fn panicCall(message: []const u8, return_address: ?usize) noreturn {
    @branchHint(.cold);
    const address = return_address orelse @returnAddress();

    if (!active) {
        active = true;
        if (lcd.panicBegin()) {
            drawScreen(message, address);
        }
    }

    lcd.panicHalt();
}

fn drawScreen(message: []const u8, return_address: ?usize) void {
    // Commit the title first so the most important information is visible even
    // if rendering the diagnostic details encounters damaged state.
    lcd.panicFill(0, 0, lcd.WIDTH, lcd.HEIGHT, background);
    drawText(margin_x, 16, .px24, ":( KERNEL PANIC");
    lcd.panicPresent();

    drawText(margin_x, 56, .px12, "The system has been halted.");
    drawText(margin_x, 80, .px12, "Reason:");
    drawWrappedReason(message);
    drawAddress(return_address);
    drawText(margin_x, 220, .px12, "Reset the board to restart.");
    lcd.panicPresent();
}

fn drawText(x: i32, y: i32, size: FontSize, text: []const u8) void {
    const metrics = size.metrics();
    var cursor_x = x;

    for (text) |byte| {
        if (byte == '\n') break;
        drawChar(cursor_x, y, size, printable(byte));
        cursor_x += metrics.w;
    }
}

fn drawChar(x: i32, y: i32, size: FontSize, ch: u8) void {
    const metrics = size.metrics();
    var row: i32 = 0;

    while (row < metrics.h) : (row += 1) {
        var col: i32 = 0;
        while (col < metrics.w) {
            while (col < metrics.w and !font.glyphLit(size, ch, col, row)) : (col += 1) {}
            if (col == metrics.w) break;

            const run_start = col;
            while (col < metrics.w and font.glyphLit(size, ch, col, row)) : (col += 1) {}

            lcd.panicFill(
                @intCast(x + run_start),
                @intCast(y + row),
                @intCast(col - run_start),
                1,
                foreground,
            );
        }
    }
}

fn printable(byte: u8) u8 {
    return if (byte >= 0x20 and byte <= 0x7E) byte else '?';
}

fn drawWrappedReason(message: []const u8) void {
    if (message.len == 0) {
        drawText(margin_x, reason_y, .px12, "(no message)");
        return;
    }

    const metrics = FontSize.px12.metrics();
    var index: usize = 0;
    var row: usize = 0;

    while (row < reason_rows and index < message.len) : (row += 1) {
        const last_row = row + 1 == reason_rows;
        const line = scanLine(message, index, reason_cols);
        const y = reason_y + @as(i32, @intCast(row)) * metrics.h;

        if (last_row and line.next < message.len) {
            drawMessageRange(margin_x, y, message, index, line.end, reason_cols - 3);
            drawText(
                margin_x + @as(i32, @intCast(reason_cols - 3)) * metrics.w,
                y,
                .px12,
                "...",
            );
            return;
        }

        drawMessageRange(margin_x, y, message, index, line.end, reason_cols);
        index = line.next;
    }
}

const ScannedLine = struct {
    end: usize,
    next: usize,
};

fn scanLine(message: []const u8, start: usize, max_cols: usize) ScannedLine {
    var index = start;
    var cols: usize = 0;

    while (index < message.len and cols < max_cols) : (index += 1) {
        switch (message[index]) {
            '\n' => return .{ .end = index, .next = index + 1 },
            '\r' => {},
            else => cols += 1,
        }
    }

    return .{ .end = index, .next = index };
}

fn drawMessageRange(x: i32, y: i32, message: []const u8, start: usize, end: usize, max_cols: usize) void {
    const metrics = FontSize.px12.metrics();
    var index = start;
    var col: usize = 0;

    while (index < end and col < max_cols) : (index += 1) {
        const byte = message[index];
        if (byte == '\r') continue;
        drawChar(x + @as(i32, @intCast(col)) * metrics.w, y, .px12, printable(byte));
        col += 1;
    }
}

fn drawAddress(return_address: ?usize) void {
    const metrics = FontSize.px12.metrics();
    const y: i32 = 196;
    const prefix = "Address: ";
    drawText(margin_x, y, .px12, prefix);

    var x = margin_x + @as(i32, @intCast(prefix.len)) * metrics.w;
    const address = return_address orelse {
        drawText(x, y, .px12, "N/A");
        return;
    };

    drawText(x, y, .px12, "0x");
    x += 2 * metrics.w;

    const hex_digits: usize = @sizeOf(usize) * 2;
    var digit: usize = hex_digits;
    while (digit > 0) {
        digit -= 1;
        const shift: std.math.Log2Int(usize) = @intCast(digit * 4);
        const value: u4 = @truncate(address >> shift);
        const value_u8: u8 = value;
        const ch: u8 = if (value < 10) '0' + value_u8 else 'A' + (value_u8 - 10);
        drawChar(x, y, .px12, ch);
        x += metrics.w;
    }
}
