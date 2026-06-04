const lcd = @import("../lcd.zig");
const font = @import("font.zig");
const Color = @import("color.zig").Color565;
const types = @import("types.zig");

const FontSize = types.FontSize;
const Rect = types.Rect;

pub const Canvas = struct {
    area: Rect,
    buf: []u16,
    clip: Rect,

    pub fn init(area: Rect, buf: []u16) Canvas {
        return .{
            .area = area,
            .buf = buf,
            .clip = area,
        };
    }

    pub fn setClip(self: *Canvas, clip: Rect) void {
        self.clip = Rect.intersect(self.area, clip) orelse Rect.init(0, 0, 0, 0);
    }

    fn indexOf(self: *const Canvas, x: i32, y: i32) usize {
        const lx: usize = @intCast(x - self.area.x);
        const ly: usize = @intCast(y - self.area.y);
        return ly * @as(usize, @intCast(self.area.w)) + lx;
    }

    fn putRaw(self: *Canvas, x: i32, y: i32, raw_color: u16) void {
        if (!self.clip.contains(x, y)) return;
        self.buf[self.indexOf(x, y)] = raw_color;
    }

    pub fn drawPoint(self: *Canvas, x: i32, y: i32, color: Color) void {
        self.putRaw(x, y, color.toRgb565());
    }

    pub fn fillRect(self: *Canvas, x: i32, y: i32, w: i32, h: i32, color: Color) void {
        if (w <= 0 or h <= 0) return;

        const draw_rect = Rect.init(x, y, w, h);
        const res = Rect.intersect(draw_rect, self.clip) orelse return;
        const raw_color = color.toRgb565();
        const row_len: usize = @intCast(res.w);

        var iy = res.y;
        while (iy < res.y + res.h) : (iy += 1) {
            const start = self.indexOf(res.x, iy);
            @memset(self.buf[start .. start + row_len], raw_color);
        }
    }

    pub fn drawHLine(self: *Canvas, x: i32, y: i32, w: i32, color: Color) void {
        self.fillRect(x, y, w, 1, color);
    }

    pub fn drawVLine(self: *Canvas, x: i32, y: i32, h: i32, color: Color) void {
        self.fillRect(x, y, 1, h, color);
    }

    pub fn drawRect(self: *Canvas, x: i32, y: i32, w: i32, h: i32, color: Color) void {
        if (w <= 0 or h <= 0) return;
        const rect = Rect.init(x, y, w, h);
        if (Rect.intersect(rect, self.clip) == null) return;

        self.drawHLine(x, y, w, color);
        if (h > 1) self.drawHLine(x, y + h - 1, w, color);
        if (h > 2) {
            self.drawVLine(x, y + 1, h - 2, color);
            if (w > 1) self.drawVLine(x + w - 1, y + 1, h - 2, color);
        }
    }

    pub fn drawLine(self: *Canvas, x1: i32, y1: i32, x2: i32, y2: i32, color: Color) void {
        if (x1 == x2) {
            self.drawVLine(x1, @min(y1, y2), types.absI32(y2 - y1) + 1, color);
            return;
        }
        if (y1 == y2) {
            self.drawHLine(@min(x1, x2), y1, types.absI32(x2 - x1) + 1, color);
            return;
        }

        const line_rect = Rect.init(
            @min(x1, x2),
            @min(y1, y2),
            types.absI32(x2 - x1) + 1,
            types.absI32(y2 - y1) + 1,
        );
        if (Rect.intersect(line_rect, self.clip) == null) return;

        var dx = x2 - x1;
        var dy = y2 - y1;
        var row = x1;
        var col = y1;

        const incx: i32 = if (dx > 0) 1 else if (dx == 0) 0 else blk: {
            dx = -dx;
            break :blk -1;
        };
        const incy: i32 = if (dy > 0) 1 else if (dy == 0) 0 else blk: {
            dy = -dy;
            break :blk -1;
        };
        const distance = @max(dx, dy);
        const raw_color = color.toRgb565();

        var xerr: i32 = 0;
        var yerr: i32 = 0;
        var i: i32 = 0;
        while (i <= distance) : (i += 1) {
            self.putRaw(row, col, raw_color);
            xerr += dx;
            yerr += dy;
            if (xerr > distance) {
                xerr -= distance;
                row += incx;
            }
            if (yerr > distance) {
                yerr -= distance;
                col += incy;
            }
        }
    }

    pub fn drawCircle(self: *Canvas, x0: i32, y0: i32, r: i32, color: Color) void {
        if (r <= 0) return;

        const circle_rect = Rect.init(x0 - r, y0 - r, r * 2 + 1, r * 2 + 1);
        if (Rect.intersect(circle_rect, self.clip) == null) return;

        const raw_color = color.toRgb565();
        var a: i32 = 0;
        var b: i32 = r;
        var di: i32 = 3 - r * 2;

        while (a <= b) {
            self.putRaw(x0 + a, y0 - b, raw_color);
            self.putRaw(x0 + b, y0 - a, raw_color);
            self.putRaw(x0 + b, y0 + a, raw_color);
            self.putRaw(x0 + a, y0 + b, raw_color);
            self.putRaw(x0 - a, y0 + b, raw_color);
            self.putRaw(x0 - b, y0 + a, raw_color);
            self.putRaw(x0 - b, y0 - a, raw_color);
            self.putRaw(x0 - a, y0 - b, raw_color);

            a += 1;
            if (di < 0) {
                di += 4 * a + 6;
            } else {
                di += 10 + 4 * (a - b);
                b -= 1;
            }
        }
    }

    fn glyphLit(comptime font_size: FontSize, ch: u8, col: i32, row: i32) bool {
        const idx: usize = @as(usize, ch - 0x20);
        const ucol: usize = @intCast(col);

        return switch (font_size) {
            .px12 => blk: {
                const val = (@as(u16, font.asc2_1206[idx][ucol * 2]) << 8) |
                    @as(u16, font.asc2_1206[idx][ucol * 2 + 1]);
                const bit_pos: u4 = @intCast(15 - row);
                break :blk ((val >> bit_pos) & 1) != 0;
            },
            .px16 => blk: {
                const val = (@as(u16, font.asc2_1608[idx][ucol * 2]) << 8) |
                    @as(u16, font.asc2_1608[idx][ucol * 2 + 1]);
                const bit_pos: u4 = @intCast(15 - row);
                break :blk ((val >> bit_pos) & 1) != 0;
            },
            .px24 => blk: {
                const val = (@as(u32, font.asc2_2412[idx][ucol * 3]) << 16) |
                    (@as(u32, font.asc2_2412[idx][ucol * 3 + 1]) << 8) |
                    @as(u32, font.asc2_2412[idx][ucol * 3 + 2]);
                const bit_pos: u5 = @intCast(23 - row);
                break :blk ((val >> bit_pos) & 1) != 0;
            },
        };
    }

    pub fn showChar(self: *Canvas, x_off: i32, y_off: i32, ch: u8, font_size: FontSize, color: Color, bg_color: ?Color) void {
        switch (font_size) {
            .px12 => self.showCharSized(x_off, y_off, ch, .px12, color, bg_color),
            .px16 => self.showCharSized(x_off, y_off, ch, .px16, color, bg_color),
            .px24 => self.showCharSized(x_off, y_off, ch, .px24, color, bg_color),
        }
    }

    fn showCharSized(self: *Canvas, x_off: i32, y_off: i32, ch: u8, comptime font_size: FontSize, color: Color, bg_color: ?Color) void {
        if (ch < 0x20 or ch > 0x7e) return;
        const metrics = types.fontMetrics(font_size);

        const char_rect = Rect.init(x_off, y_off, metrics.w, metrics.h);
        const res = Rect.intersect(char_rect, self.clip) orelse return;
        const raw_color = color.toRgb565();
        const raw_bg = if (bg_color) |bg| bg.toRgb565() else null;

        var y = res.y;
        while (y < res.y + res.h) : (y += 1) {
            const row = y - y_off;
            var x = res.x;
            while (x < res.x + res.w) : (x += 1) {
                const col = x - x_off;
                if (glyphLit(font_size, ch, col, row)) {
                    self.buf[self.indexOf(x, y)] = raw_color;
                } else if (raw_bg) |bg| {
                    self.buf[self.indexOf(x, y)] = bg;
                }
            }
        }
    }

    pub fn showString(self: *Canvas, x_off: i32, y_off: i32, font_size: FontSize, str: []const u8, color: Color, bg_color: ?Color) void {
        switch (font_size) {
            .px12 => self.showStringSized(x_off, y_off, .px12, str, color, bg_color),
            .px16 => self.showStringSized(x_off, y_off, .px16, str, color, bg_color),
            .px24 => self.showStringSized(x_off, y_off, .px24, str, color, bg_color),
        }
    }

    fn showStringSized(self: *Canvas, x_off: i32, y_off: i32, comptime font_size: FontSize, str: []const u8, color: Color, bg_color: ?Color) void {
        const metrics = types.fontMetrics(font_size);
        var cx = x_off;
        var cy = y_off;

        for (str) |ch| {
            if (ch == '\n') {
                cx = x_off;
                cy += metrics.h;
                continue;
            }
            self.showCharSized(cx, cy, ch, font_size, color, bg_color);
            cx += metrics.w;
        }
    }

    pub fn drawImageRgb565(self: *Canvas, x: i32, y: i32, w: i32, h: i32, pixels: []const u16, stride: i32, color_key: ?u16) void {
        if (w <= 0 or h <= 0 or stride < w) return;
        const img_rect = Rect.init(x, y, w, h);
        const res = Rect.intersect(img_rect, self.clip) orelse return;
        const row_len: usize = @intCast(res.w);

        var iy = res.y;
        while (iy < res.y + res.h) : (iy += 1) {
            const src_x: usize = @intCast(res.x - x);
            const src_y: usize = @intCast(iy - y);
            const src_start = src_y * @as(usize, @intCast(stride)) + src_x;
            const dst_start = self.indexOf(res.x, iy);

            if (color_key == null) {
                @memcpy(self.buf[dst_start .. dst_start + row_len], pixels[src_start .. src_start + row_len]);
            } else {
                const key = color_key.?;
                var ix: usize = 0;
                while (ix < row_len) : (ix += 1) {
                    const px = pixels[src_start + ix];
                    if (px != key) self.buf[dst_start + ix] = px;
                }
            }
        }
    }

    pub fn flush(self: *Canvas) void {
        lcd.flushPixels(
            @intCast(self.area.x),
            @intCast(self.area.y),
            @intCast(self.area.x + self.area.w - 1),
            @intCast(self.area.y + self.area.h - 1),
            self.buf.ptr,
        );
    }
};
