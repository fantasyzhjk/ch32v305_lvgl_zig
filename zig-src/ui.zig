const std = @import("std");
const lcd = @import("lcd.zig");
const font = @import("font.zig");

pub const Rect = struct {
    x: u16,
    y: u16,
    w: u16,
    h: u16,

    pub fn unionRect(a: Rect, b: Rect) Rect {
        const x1 = @min(a.x, b.x);
        const y1 = @min(a.y, b.y);
        const x2 = @max(a.x + a.w, b.x + b.w);
        const y2 = @max(a.y + a.h, b.y + b.h);
        return .{
            .x = x1,
            .y = y1,
            .w = x2 - x1,
            .h = y2 - y1,
        };
    }
};

/// A Canvas represents a memory buffer for a specific rectangular zone on the screen.
/// Drawing operations manipulate the buffer directly, enabling fast CPU rendering.
/// Call `flush()` to push the entire rendered buffer to the LCD via DMA.
pub const Canvas = struct {
    x: u16,
    y: u16,
    w: u16,
    h: u16,
    buf: []u16,

    pub fn init(x: u16, y: u16, w: u16, h: u16, buf: []u16) Canvas {
        return .{ .x = x, .y = y, .w = w, .h = h, .buf = buf };
    }

    /// Dynamically allocates a memory buffer for the Canvas using the provided allocator.
    pub fn create(allocator: std.mem.Allocator, x: u16, y: u16, w: u16, h: u16) !Canvas {
        const size: usize = @as(usize, w) * @as(usize, h);
        const buf = try allocator.alloc(u16, size);
        return Canvas{ .x = x, .y = y, .w = w, .h = h, .buf = buf };
    }

    /// Frees the dynamically allocated memory buffer.
    pub fn destroy(self: *Canvas, allocator: std.mem.Allocator) void {
        allocator.free(self.buf);
    }

    pub fn clear(self: *Canvas, color: u16) void {
        for (self.buf) |*p| p.* = color;
    }

    pub fn drawPoint(self: *Canvas, cx: i32, cy: i32, color: u16) void {
        if (cx >= 0 and cx < self.w and cy >= 0 and cy < self.h) {
            self.buf[@as(usize, @intCast(cy)) * @as(usize, self.w) + @as(usize, @intCast(cx))] = color;
        }
    }

    pub fn drawRect(self: *Canvas, cx: i32, cy: i32, cw: u16, ch: u16, color: u16) void {
        // top and bottom
        for (0..cw) |i| {
            self.drawPoint(cx + @as(i32, @intCast(i)), cy, color);
            self.drawPoint(cx + @as(i32, @intCast(i)), cy + ch - 1, color);
        }
        // left and right
        for (0..ch) |i| {
            self.drawPoint(cx, cy + @as(i32, @intCast(i)), color);
            self.drawPoint(cx + cw - 1, cy + @as(i32, @intCast(i)), color);
        }
    }

    pub fn fillRect(self: *Canvas, cx: i32, cy: i32, cw: u16, ch: u16, color: u16) void {
        var iy: i32 = 0;
        while (iy < ch) : (iy += 1) {
            var ix: i32 = 0;
            while (ix < cw) : (ix += 1) {
                self.drawPoint(cx + ix, cy + iy, color);
            }
        }
    }

    pub fn showChar(self: *Canvas, x_off: i32, y_off: i32, ch: u8, size: u32, color: u16, bg_color: ?u16) void {
        if (ch < 0x20 or ch > 0x7e) return;

        const w: i32 = switch (size) {
            12 => 6,
            16 => 8,
            24 => 12,
            else => return,
        };
        const h: i32 = @intCast(size);
        const idx: usize = @as(usize, ch - 0x20);

        var row: i32 = 0;
        while (row < h) : (row += 1) {
            var col: i32 = 0;
            while (col < w) : (col += 1) {
                const urow: u16 = @intCast(row);
                const ucol: u16 = @intCast(col);
                const lit = switch (size) {
                    12 => blk: {
                        const val = (@as(u16, font.asc2_1206[idx][ucol*2]) << 8) | @as(u16, font.asc2_1206[idx][ucol*2+1]);
                        const bit_pos: u4 = @intCast(15 - urow);
                        break :blk ((val >> bit_pos) & 1) != 0;
                    },
                    16 => blk: {
                        const val = (@as(u16, font.asc2_1608[idx][ucol*2]) << 8) | @as(u16, font.asc2_1608[idx][ucol*2+1]);
                        const bit_pos: u4 = @intCast(15 - urow);
                        break :blk ((val >> bit_pos) & 1) != 0;
                    },
                    24 => blk: {
                         const val = (@as(u32, font.asc2_2412[idx][ucol*3]) << 16) | 
                                     (@as(u32, font.asc2_2412[idx][ucol*3+1]) << 8) | 
                                     @as(u32, font.asc2_2412[idx][ucol*3+2]);
                         const bit_pos: u5 = @intCast(23 - urow);
                         break :blk ((val >> bit_pos) & 1) != 0;
                    },
                    else => false,
                };
                if (lit) {
                    self.drawPoint(x_off + col, y_off + row, color);
                } else if (bg_color) |bg| {
                    self.drawPoint(x_off + col, y_off + row, bg);
                }
            }
        }
    }

    pub fn showString(self: *Canvas, x_off: i32, y_off: i32, size: u32, str: []const u8, color: u16, bg_color: ?u16) void {
        const w: i32 = switch (size) {
            12 => 6,
            16 => 8,
            24 => 12,
            else => return,
        };
        var cx = x_off;
        var cy = y_off;
        for (str) |ch| {
            if (ch == '\n') {
                cx = x_off;
                cy += @intCast(size);
                continue;
            }
            self.showChar(cx, cy, ch, size, color, bg_color);
            cx += w;
        }
    }

    pub fn showNum(self: *Canvas, x_off: i32, y_off: i32, num: u32, size: u32, color: u16, bg_color: ?u16) void {
        var buf: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d}", .{num}) catch return;
        self.showString(x_off, y_off, size, s, color, bg_color);
    }

    /// Flushes the local RAM buffer to the LCD via hardware DMA.
    pub fn flush(self: *Canvas) void {
        lcd.flushPixels(self.x, self.y, self.x + self.w - 1, self.y + self.h - 1, self.buf.ptr);
    }
};