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

    pub fn glyphLit(font_size: FontSize, ch: u8, col: i32, row: i32) bool {
        if (ch < 0x20 or ch > 0x7e or col < 0 or row < 0) return false;
        const m = font_size.metrics();
        if (col >= m.w or row >= m.h) return false;

        const idx: usize = @intCast(ch - 0x20);
        const c: usize = @intCast(col);
        const val: u32 = switch (font_size) {
            .px12 => (@as(u32, font.asc2_1206[idx][c * 2]) << 8) | @as(u32, font.asc2_1206[idx][c * 2 + 1]),
            .px16 => (@as(u32, font.asc2_1608[idx][c * 2]) << 8) | @as(u32, font.asc2_1608[idx][c * 2 + 1]),
            .px24 => (@as(u32, font.asc2_2412[idx][c * 3]) << 16) | (@as(u32, font.asc2_2412[idx][c * 3 + 1]) << 8) | @as(u32, font.asc2_2412[idx][c * 3 + 2]),
        };
        const total_bits: u32 = switch (font_size) {
            .px12 => 16,
            .px16 => 16,
            .px24 => 24,
        };
        const bit_pos: u5 = @intCast(total_bits - 1 - @as(u32, @intCast(row)));
        return ((val >> bit_pos) & 1) != 0;
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

    /// 将文字作为纹理贴到任意四边形上（3D 文字效果，仿射近似）
    /// quad: 四边形的 4 个屏幕坐标点（顺序：左上→右上→右下→左下）
    pub fn drawTextOnQuad(self: *Canvas, quad: [4]types.Point, str: []const u8, comptime font_size: FontSize, color: Color) void {
        const m = comptime font_size.metrics();
        if (str.len == 0) return;

        const p = quad;
        const raw_color = color.toRgb565();
        const buf_stride: usize = @intCast(self.area.w);
        const clip_x_min = self.clip.x;
        const clip_x_max = self.clip.x + self.clip.w - 1;
        const clip_y_min = self.clip.y;
        const clip_y_max = self.clip.y + self.clip.h - 1;

        // 文字区域：宽度占面 80%，高度按宽高比计算，保持字体比例
        const text_w_px: f32 = @floatFromInt(@as(i32, @intCast(str.len)) * m.w);
        const text_h_px: f32 = @floatFromInt(m.h);
        const uv_frac_u: f32 = 0.8;
        const uv_frac_v: f32 = uv_frac_u * text_h_px / text_w_px; // 保持比例
        const uv_off_u: f32 = (1.0 - uv_frac_u) / 2.0;
        const uv_off_v: f32 = (1.0 - uv_frac_v) / 2.0;

        // 仿射系数: screen = p0 + u*(p1-p0) + v*(p3-p0)
        const du_x: f32 = @floatFromInt(p[1].x - p[0].x);
        const du_y: f32 = @floatFromInt(p[1].y - p[0].y);
        const dv_x: f32 = @floatFromInt(p[3].x - p[0].x);
        const dv_y: f32 = @floatFromInt(p[3].y - p[0].y);
        const p0xf: f32 = @floatFromInt(p[0].x);
        const p0yf: f32 = @floatFromInt(p[0].y);

        // comptime 字符尺寸
        const char_w: comptime_int = m.w;
        const char_h: comptime_int = m.h;

        // 逐字符渲染
        var ci: usize = 0;
        while (ci < str.len) : (ci += 1) {
            // 该字符在文字区域内的 UV 范围
            const fu0 = uv_off_u + @as(f32, @floatFromInt(@as(i32, @intCast(ci)) * @as(i32, char_w))) / text_w_px * uv_frac_u;
            const fu1 = uv_off_u + @as(f32, @floatFromInt(@as(i32, @intCast(ci + 1)) * @as(i32, char_w))) / text_w_px * uv_frac_u;
            const fv0 = uv_off_v;
            const fv1 = uv_off_v + uv_frac_v;

            // 字符四角的屏幕坐标（仿射映射）
            const sx0: i32 = @intFromFloat(p0xf + fu0 * du_x + fv0 * dv_x);
            const sy0: i32 = @intFromFloat(p0yf + fu0 * du_y + fv0 * dv_y);
            const sx1: i32 = @intFromFloat(p0xf + fu1 * du_x + fv0 * dv_x);
            const sy1: i32 = @intFromFloat(p0yf + fu1 * du_y + fv0 * dv_y);
            const sx2: i32 = @intFromFloat(p0xf + fu1 * du_x + fv1 * dv_x);
            const sy2: i32 = @intFromFloat(p0yf + fu1 * du_y + fv1 * dv_y);
            const sx3: i32 = @intFromFloat(p0xf + fu0 * du_x + fv1 * dv_x);
            const sy3: i32 = @intFromFloat(p0yf + fu0 * du_y + fv1 * dv_y);

            // 包围盒 + 裁剪
            var min_sx = @min(sx0, @min(sx1, @min(sx2, sx3)));
            var max_sx = @max(sx0, @max(sx1, @max(sx2, sx3)));
            var min_sy = @min(sy0, @min(sy1, @min(sy2, sy3)));
            var max_sy = @max(sy0, @max(sy1, @max(sy2, sy3)));
            if (min_sx < clip_x_min) min_sx = clip_x_min;
            if (max_sx > clip_x_max) max_sx = clip_x_max;
            if (min_sy < clip_y_min) min_sy = clip_y_min;
            if (max_sy > clip_y_max) max_sy = clip_y_max;
            if (min_sx > max_sx or min_sy > max_sy) continue;

            // 逆仿射：从屏幕像素反求该字符内的 (cu, cv) ∈ [0,1]
            const cu_dx: f32 = du_x * (fu1 - fu0);
            const cu_dy: f32 = du_y * (fu1 - fu0);
            const cv_dx: f32 = dv_x * (fv1 - fv0);
            const cv_dy: f32 = dv_y * (fv1 - fv0);
            const det = cu_dx * cv_dy - cu_dy * cv_dx;
            if (@abs(det) < 1e-6) continue;
            const inv_det = 1.0 / det;
            const inv_cx = cv_dy * inv_det;
            const inv_cy = -cv_dx * inv_det;
            const inv_vx = -cu_dy * inv_det;
            const inv_vy = cu_dx * inv_det;
            const char_p0_x = p0xf + fu0 * du_x + fv0 * dv_x;
            const char_p0_y = p0yf + fu0 * du_y + fv0 * dv_y;

            var sy_i = min_sy;
            while (sy_i <= max_sy) : (sy_i += 1) {
                const dy_f = (@as(f32, @floatFromInt(sy_i)) + 0.5) - char_p0_y;
                var sx_i = min_sx;
                while (sx_i <= max_sx) : (sx_i += 1) {
                    const dx_f = (@as(f32, @floatFromInt(sx_i)) + 0.5) - char_p0_x;
                    const cu = inv_cx * dx_f + inv_cy * dy_f;
                    const cv = inv_vx * dx_f + inv_vy * dy_f;
                    if (cu < 0.0 or cu >= 1.0 or cv < 0.0 or cv >= 1.0) continue;

                    const px_x: i32 = @intFromFloat(cu * @as(f32, @floatFromInt(@as(i32, char_w))));
                    const px_y: i32 = @intFromFloat(cv * @as(f32, @floatFromInt(@as(i32, char_h))));
                    if (px_x < 0 or px_y < 0 or px_x >= @as(i32, char_w) or px_y >= @as(i32, char_h)) continue;

                    if (glyphLit(font_size, str[ci], px_x, px_y)) {
                        const lx: usize = @intCast(sx_i - self.area.x);
                        const ly: usize = @intCast(sy_i - self.area.y);
                        self.buf[ly * buf_stride + lx] = raw_color;
                    }
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
