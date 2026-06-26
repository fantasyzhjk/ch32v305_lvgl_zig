//! Fast RGB565 post-process effects for the embedded display pipeline.
//!
//! These presets intentionally avoid floating point, heap allocation, source
//! resampling and framebuffer copies. They are designed to be assigned directly
//! to `Display.post_render`.

const Rect = @import("types.zig").Rect;

const screen_w = 240;
const screen_h = 240;

inline fn rgb565From8(comptime r: u8, comptime g: u8, comptime b: u8) u16 {
    return (@as(u16, r >> 3) << 11) | (@as(u16, g >> 2) << 5) | @as(u16, b >> 3);
}

inline fn packRgb565(r5: u16, g6: u16, b5: u16) u16 {
    return (r5 << 11) | (g6 << 5) | b5;
}

inline fn scale5(v: u32, q8: u32) u16 {
    return @intCast(@min((v * q8 + 128) >> 8, 31));
}

inline fn scale6(v: u32, q8: u32) u16 {
    return @intCast(@min((v * q8 + 128) >> 8, 63));
}

inline fn scaleRgb565(px: u16, q8: u32) u16 {
    return packRgb565(
        scale5(px >> 11, q8),
        scale6((px >> 5) & 0x3f, q8),
        scale5(px & 0x1f, q8),
    );
}

inline fn scaleRgb565Channels(px: u16, qr: u32, qg: u32, qb: u32) u16 {
    return packRgb565(
        scale5(px >> 11, qr),
        scale6((px >> 5) & 0x3f, qg),
        scale5(px & 0x1f, qb),
    );
}

inline fn mulQ8(a: u32, b: u32) u32 {
    return (a * b + 128) >> 8;
}

inline fn absI32(v: i32) i32 {
    return if (v < 0) -v else v;
}

inline fn min4I32(a: i32, b: i32, c: i32, d: i32) i32 {
    return @min(@min(a, b), @min(c, d));
}

inline fn edgeQ8(x: i32, y: i32, min_q8: u32) u32 {
    const d = min4I32(x, y, screen_w - 1 - x, screen_h - 1 - y);
    if (d <= 0) return min_q8;
    if (d >= 32) return 256;
    return min_q8 + ((@as(u32, @intCast(d)) * (256 - min_q8)) >> 5);
}

inline fn tinyNoiseQ8(x: i32, y: i32, base: u32, amount: u32) u32 {
    const n: u32 = @intCast((x *% 13 + y *% 17) & 0x3);
    return base + n * amount;
}

/// Fast CRT-style RGB565 post-process.
///
/// Costs one read and one write per pixel, with integer-only scanlines,
/// phosphor mask, subtle edge falloff, diagonal sheen and static grain.
pub fn crtPostRender(buf: []u16, stride: i32, rect: Rect) void {
    var ly: i32 = 0;
    while (ly < rect.h) : (ly += 1) {
        const sy = rect.y + ly;
        const row_start: usize = @intCast(ly * stride);
        const scan_q8: u32 = if ((sy & 1) == 0) 212 else 256;

        var lx: i32 = 0;
        while (lx < rect.w) : (lx += 1) {
            const sx = rect.x + lx;
            const idx = row_start + @as(usize, @intCast(lx));

            var gain = scan_q8;
            gain = mulQ8(gain, edgeQ8(sx, sy, 176));

            const sheen_axis = sx + @divTrunc(sy, 2);
            const sheen_dist = absI32(sheen_axis - 156);
            if (sheen_dist < 18) gain = mulQ8(gain, 276);

            gain = mulQ8(gain, tinyNoiseQ8(sx, sy, 250, 3));

            const grille = sx & 3;
            const mr: u32 = if (grille == 0) 292 else 214;
            const mg: u32 = if (grille == 1) 276 else 224;
            const mb: u32 = if (grille == 2) 276 else 194;

            buf[idx] = scaleRgb565Channels(
                buf[idx],
                mulQ8(gain, mr),
                mulQ8(gain, mg),
                mulQ8(gain, mb),
            );
        }
    }
}

const gb_palette = [_]u16{
    rgb565From8(15, 56, 15),
    rgb565From8(48, 98, 48),
    rgb565From8(139, 172, 15),
    rgb565From8(155, 188, 15),
};

inline fn gameBoyLevel(px: u16) u2 {
    const r5: u32 = px >> 11;
    const g6: u32 = (px >> 5) & 0x3f;
    const b5: u32 = px & 0x1f;
    const r = (r5 << 3) | (r5 >> 2);
    const g = (g6 << 2) | (g6 >> 4);
    const b = (b5 << 3) | (b5 >> 2);
    const light2 = @min(@min(r, g), b) + @max(@max(r, g), b);

    if (light2 < 109) return 0;
    if (light2 < 167) return 1;
    if (light2 <= 195) return 2;
    return 3;
}

inline fn gameBoyPixelSpan(pos: i32, limit: i32) i32 {
    return @min(2 - (pos & 1), limit);
}

/// Fast Game Boy-style RGB565 post-process based on HSL lightness.
///
/// Converts source pixels to the nearest of the four DMG green palette
/// luminance levels using `(min(rgb) + max(rgb)) / 2`, matching the shader
/// logic while staying integer-only. A light 2x2 pixelation keeps the handheld
/// look without making the 240x240 LCD feel too blocky.
pub fn gameBoyPostRender(buf: []u16, stride: i32, rect: Rect) void {
    var ly: i32 = 0;
    while (ly < rect.h) {
        const sy = rect.y + ly;
        const block_h = gameBoyPixelSpan(sy, rect.h - ly);

        var lx: i32 = 0;
        while (lx < rect.w) {
            const sx = rect.x + lx;
            const block_w = gameBoyPixelSpan(sx, rect.w - lx);
            const source_idx: usize = @intCast(ly * stride + lx);
            const base = gb_palette[gameBoyLevel(buf[source_idx])];

            var by: i32 = 0;
            while (by < block_h) : (by += 1) {
                const row_start: usize = @intCast((ly + by) * stride + lx);

                var bx: i32 = 0;
                while (bx < block_w) : (bx += 1) {
                    buf[row_start + @as(usize, @intCast(bx))] = base;
                }
            }

            lx += block_w;
        }

        ly += block_h;
    }
}

test "post render effects run on a small buffer" {
    var buf = [_]u16{
        0x0000, 0x001f, 0x07e0, 0xf800,
        0xffff, 0x8410, 0xffe0, 0xf81f,
        0x07ff, 0x4208, 0x2104, 0xdefb,
        0x18e3, 0x39e7, 0x6318, 0x9cf3,
    };
    const rect = Rect.init(0, 0, 4, 4);
    gameBoyPostRender(&buf, 4, rect);
}
