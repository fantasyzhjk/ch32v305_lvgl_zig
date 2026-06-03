const std = @import("std");
const ch32 = @import("ch32.zig");
const hal = ch32.hal;
const c = ch32.c;
const font = @import("font.zig");

pub const WIDTH: u16 = 240;
pub const HEIGHT: u16 = 240;

const USE_HORIZONTAL: comptime_int = 0;

pub const Color = struct {
    pub const WHITE: u16 = 0xFFFF;
    pub const BLACK: u16 = 0x0000;
    pub const BLUE: u16 = 0x001F;
    pub const RED: u16 = 0xF800;
    pub const MAGENTA: u16 = 0xF81F;
    pub const GREEN: u16 = 0x07E0;
    pub const CYAN: u16 = 0x7FFF;
    pub const YELLOW: u16 = 0xFFE0;
    pub const ORANGE: u16 = 0xFD20;
    pub const PURPLE: u16 = 0x8010;
    pub const GRAY: u16 = 0x8430;
    pub const LGRAY: u16 = 0xC618;
    pub const GOLD: u16 = 0xFEA0;
    pub const SILVER: u16 = 0xC618;
};

pub var back_color: u16 = Color.BLACK;
pub var fore_color: u16 = Color.WHITE;

// ── SPI helpers ──────────────────────────────────────────────────
fn spiWaitBusIdle() void {
    while (hal.SPI_I2S_GetFlagStatus(hal.SPI2, hal.SPI_I2S_FLAG_BSY) == hal.SET) {}
}

fn spiWaitTx() void {
    while (hal.SPI_I2S_GetFlagStatus(hal.SPI2, hal.SPI_I2S_FLAG_TXE) == hal.RESET) {}
}

fn writeBusOnly(dat: u8) void {
    spiWaitTx();
    hal.SPI_I2S_SendData(hal.SPI2, dat);
}

fn writeBus(dat: u8) void {
    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_12, hal.Bit_RESET);
    writeBusOnly(dat);
    spiWaitBusIdle();
    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_12, hal.Bit_SET);
}

fn writeData8(dat: u8) void {
    writeBus(dat);
}

fn writeData16(dat: u16) void {
    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_12, hal.Bit_RESET);
    writeBusOnly(@intCast(dat >> 8));
    writeBusOnly(@intCast(dat & 0xFF));
    spiWaitBusIdle();
    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_12, hal.Bit_SET);
}

fn writeReg(dat: u8) void {
    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_10, hal.Bit_RESET);
    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_12, hal.Bit_RESET);

    writeBusOnly(dat);
    spiWaitBusIdle();

    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_12, hal.Bit_SET);
    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_10, hal.Bit_SET);
}

// ── Core operations ──────────────────────────────────────────────

pub fn addressSet(x1: u16, y1: u16, x2: u16, y2: u16) void {
    const x_off: u16 = if (USE_HORIZONTAL == 1 or USE_HORIZONTAL == 3) 80 else 0;
    const y_off: u16 = if (USE_HORIZONTAL == 1) 80 else 0;

    writeReg(0x2A);
    writeData16(x1 + x_off);
    writeData16(x2 + x_off);
    writeReg(0x2B);
    writeData16(y1 + y_off);
    writeData16(y2 + y_off);
    writeReg(0x2C);
}

pub fn fill(xsta: u16, ysta: u16, xend: u16, yend: u16, color: u16) void {
    addressSet(xsta, ysta, xend - 1, yend - 1);

    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_12, hal.Bit_RESET);

    const count: u32 = @as(u32, xend - xsta) * @as(u32, yend - ysta);

    // Switch SPI to 16-bit mode for DMA
    hal.SPI_Cmd(hal.SPI2, hal.DISABLE);
    hal.SPI_DataSizeConfig(hal.SPI2, hal.SPI_DataSize_16b);
    hal.SPI_Cmd(hal.SPI2, hal.ENABLE);

    var remaining = count;
    while (remaining > 0) {
        const chunk_size: u16 = if (remaining > 65535) 65535 else @intCast(remaining);

        hal.DMA_Cmd(hal.DMA1_Channel5, hal.DISABLE);
        while ((hal.DMA1_Channel5.*.CFGR & 1) != 0) {}
        hal.DMA_ClearITPendingBit(hal.DMA1_IT_GL5);
        const dma_done = dmaTcCount();

        // For filling, we do NOT increment memory. We read the same color variable repeatedly.
        hal.DMA1_Channel5.*.CFGR &= ~hal.DMA_MemoryInc_Enable; // Clear MINC bit
        hal.DMA1_Channel5.*.MADDR = @intFromPtr(&color);
        hal.DMA1_Channel5.*.CNTR = chunk_size;

        hal.SPI_I2S_DMACmd(hal.SPI2, hal.SPI_I2S_DMAReq_Tx, hal.ENABLE);

        hal.DMA_Cmd(hal.DMA1_Channel5, hal.ENABLE);

        waitDmaTc(dma_done);

        remaining -= chunk_size;
    }

    // Restore DMA setting for future writePixels calls
    hal.DMA_Cmd(hal.DMA1_Channel5, hal.DISABLE);
    hal.DMA1_Channel5.*.CFGR |= hal.DMA_MemoryInc_Enable;

    spiWaitBusIdle();

    hal.SPI_Cmd(hal.SPI2, hal.DISABLE);
    hal.SPI_DataSizeConfig(hal.SPI2, hal.SPI_DataSize_8b);
    hal.SPI_Cmd(hal.SPI2, hal.ENABLE);

    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_12, hal.Bit_SET);
}

pub fn writePixels(pixels: [*]const u16, count: u32) void {
    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_12, hal.Bit_RESET);

    // Switch SPI to 16-bit mode for DMA
    hal.SPI_Cmd(hal.SPI2, hal.DISABLE);
    hal.SPI_DataSizeConfig(hal.SPI2, hal.SPI_DataSize_16b);
    hal.SPI_Cmd(hal.SPI2, hal.ENABLE);

    var remaining = count;
    var current_ptr = pixels;

    while (remaining > 0) {
        const chunk_size: u16 = if (remaining > 65535) 65535 else @intCast(remaining);

        hal.DMA_Cmd(hal.DMA1_Channel5, hal.DISABLE);
        while ((hal.DMA1_Channel5.*.CFGR & 1) != 0) {}
        hal.DMA_ClearITPendingBit(hal.DMA1_IT_GL5);
        const dma_done = dmaTcCount();
        hal.DMA1_Channel5.*.MADDR = @intFromPtr(current_ptr);
        hal.DMA1_Channel5.*.CNTR = chunk_size;

        hal.SPI_I2S_DMACmd(hal.SPI2, hal.SPI_I2S_DMAReq_Tx, hal.ENABLE);

        hal.DMA_Cmd(hal.DMA1_Channel5, hal.ENABLE);

        waitDmaTc(dma_done);

        remaining -= chunk_size;
        current_ptr += chunk_size;
    }

    // Wait for SPI bus to become completely idle before ending
    spiWaitBusIdle();

    // Revert SPI to 8-bit mode
    hal.SPI_Cmd(hal.SPI2, hal.DISABLE);
    hal.SPI_DataSizeConfig(hal.SPI2, hal.SPI_DataSize_8b);
    hal.SPI_Cmd(hal.SPI2, hal.ENABLE);

    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_12, hal.Bit_SET);
}

pub fn flushPixels(x1: u16, y1: u16, x2: u16, y2: u16, pixels: [*]const u16) void {
    const count: u32 = @as(u32, x2 - x1 + 1) * @as(u32, y2 - y1 + 1);
    addressSet(x1, y1, x2, y2);
    writePixels(pixels, count);
}

pub fn setBrightness(brightness: u8) void {
    hal.TIM_SetCompare2(hal.TIM1, @min(brightness, 100));
}

fn writeHalfWord(color: u16) void {
    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_12, hal.Bit_RESET);

    writeBusOnly(@intCast(color >> 8));
    writeBusOnly(@intCast(color & 0xFF));

    spiWaitBusIdle();
    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_12, hal.Bit_SET);
}

// ── Drawing primitives ───────────────────────────────────────────

pub fn drawPoint(x: u16, y: u16) void {
    addressSet(x, y, x, y);
    writeData16(fore_color);
}

pub fn drawPointColor(x: u16, y: u16, color: u16) void {
    addressSet(x, y, x, y);
    writeData16(color);
}

pub fn drawLine(x1: u16, y1: u16, x2: u16, y2: u16) void {
    if (y1 == y2) {
        addressSet(x1, y1, x2, y2);
        var i: u16 = x1;
        while (i <= x2) : (i += 1) {
            writeHalfWord(fore_color);
        }
        return;
    }

    var dx: i32 = @as(i32, x2) - @as(i32, x1);
    var dy: i32 = @as(i32, y2) - @as(i32, y1);
    var row: i32 = x1;
    var col: i32 = y1;

    const incx: i32 = if (dx > 0) 1 else if (dx == 0) 0 else blk: {
        dx = -dx;
        break :blk -1;
    };
    const incy: i32 = if (dy > 0) 1 else if (dy == 0) 0 else blk: {
        dy = -dy;
        break :blk -1;
    };
    const distance = @max(dx, dy);

    var xerr: i32 = 0;
    var yerr: i32 = 0;
    for (0..@intCast(distance + 1)) |_| {
        drawPoint(@intCast(row), @intCast(col));
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

pub fn drawRectangle(x1: u16, y1: u16, x2: u16, y2: u16) void {
    drawLine(x1, y1, x2, y1);
    drawLine(x1, y1, x1, y2);
    drawLine(x1, y2, x2, y2);
    drawLine(x2, y1, x2, y2);
}

pub fn drawCircle(x0: u16, y0: u16, r: u8) void {
    var a: i32 = 0;
    var b: i32 = r;
    var di: i32 = 3 - @as(i32, r) * 2;

    while (a <= b) {
        inline for (&[_][2]i32{
            .{ -b, -a }, .{ b, -a }, .{ -a, b }, .{ -b, -a },
            .{ -a, -b }, .{ b, a },  .{ a, -b }, .{ a, b },
            .{ -b, a },
        }) |offset| {
            drawPoint(@intCast(@as(i32, x0) + offset[0]), @intCast(@as(i32, y0) + offset[1]));
        }
        a += 1;
        if (di < 0) {
            di += 4 * a + 6;
        } else {
            di += 10 + 4 * (a - b);
            b -= 1;
        }
        drawPoint(@intCast(@as(i32, x0) + a), @intCast(@as(i32, y0) + b));
    }
}

// ── Text rendering ───────────────────────────────────────────────

fn drawGlyphBitmap16(glyph: []const u8, w: u16, h: u16) void {
    for (0..h) |row| {
        for (0..w) |col| {
            const i = col * 2;
            const val: u16 =
                (@as(u16, glyph[i]) << 8) |
                @as(u16, glyph[i + 1]);

            const bit_pos: u4 = @intCast(15 - row);
            const lit = ((val >> bit_pos) & 1) != 0;

            writeHalfWord(if (lit) fore_color else back_color);
        }
    }
}

fn drawGlyphBitmap24(glyph: []const u8, w: u16, h: u16) void {
    for (0..h) |row| {
        for (0..w) |col| {
            const i = col * 3;

            const val: u32 =
                (@as(u32, glyph[i]) << 16) |
                (@as(u32, glyph[i + 1]) << 8) |
                @as(u32, glyph[i + 2]);

            const bit_pos: u5 = @intCast(23 - row);
            const lit = ((val >> bit_pos) & 1) != 0;

            writeHalfWord(if (lit) fore_color else back_color);
        }
    }
}

fn showChar(x: u16, y: u16, ch: u8, size: u32) void {
    if (ch < 0x20 or ch > 0x7e) return;

    const w: u16 = switch (size) {
        12 => 6,
        16 => 8,
        24 => 12,
        else => return,
    };

    const h: u16 = @intCast(size);

    if (x > WIDTH - w or y > HEIGHT - h) return;

    const idx: usize = @as(usize, ch - 0x20);

    const x2 = x + w - 1;
    const y2 = y + h - 1;

    addressSet(x, y, x2, y2);

    switch (size) {
        12 => drawGlyphBitmap16(font.asc2_1206[idx][0..], 6, 12),
        16 => drawGlyphBitmap16(font.asc2_1608[idx][0..], 8, 16),
        24 => drawGlyphBitmap24(font.asc2_2412[idx][0..], 12, 24),
        else => unreachable,
    }
}

pub fn showNum(x: u16, y: u16, num: u32, len: u8, size: u32) void {
    _ = len;
    var buf: [32]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{num}) catch return;
    showString(x, y, size, s);
}

pub fn showString(x: u16, y: u16, size: u32, str: []const u8) void {
    const w: u16 = switch (size) {
        12 => 6,
        16 => 8,
        24 => 12,
        else => return,
    };

    const h: u16 = @intCast(size);

    var cx = x;
    var cy = y;

    for (str) |ch| {
        if (ch == '\n') {
            cx = x;
            cy += h;
            continue;
        }

        if (cx > WIDTH - w) {
            cx = x;
            cy += h;
        }

        if (cy > HEIGHT - h) {
            cx = x;
            cy = y;
            fill(0, 0, WIDTH - 1, HEIGHT - 1, Color.RED);
        }

        showChar(cx, cy, ch, size);
        cx += w;
    }
}

pub fn showImage(x: u16, y: u16, length: u16, wide: u16, data: [*]const u8) void {
    if (x + length > WIDTH or y + wide > HEIGHT) return;
    addressSet(x, y, x + length - 1, y + wide - 1);
    for (0..@as(u32, length) * @as(u32, wide) * 2) |i| {
        writeBus(data[i]);
    }
}

// ── Display control ──────────────────────────────────────────────

pub fn displayOn() void {
    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_14, hal.Bit_SET);
}

pub fn displayOff() void {
    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_14, hal.Bit_RESET);
}

pub fn enterSleep() void {
    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_14, hal.Bit_RESET);
    c.Delay_Ms(5);
    writeReg(0x10);
}

pub fn exitSleep() void {
    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_14, hal.Bit_SET);
    c.Delay_Ms(5);
    writeReg(0x11);
    c.Delay_Ms(120);
}

// ── Hardware init ────────────────────────────────────────────────

fn initGpio() void {
    var gpio: hal.GPIO_InitTypeDef = .{ .GPIO_Pin = 0, .GPIO_Speed = 0, .GPIO_Mode = 0 };
    var spi: hal.SPI_InitTypeDef = .{
        .SPI_Direction = 0,
        .SPI_Mode = 0,
        .SPI_DataSize = 0,
        .SPI_CPOL = 0,
        .SPI_CPHA = 0,
        .SPI_NSS = 0,
        .SPI_BaudRatePrescaler = 0,
        .SPI_FirstBit = 0,
        .SPI_CRCPolynomial = 0,
    };

    hal.RCC_APB2PeriphClockCmd(hal.RCC_APB2Periph_GPIOB, hal.ENABLE);
    hal.RCC_APB1PeriphClockCmd(hal.RCC_APB1Periph_SPI2, hal.ENABLE);

    gpio.GPIO_Pin = hal.GPIO_Pin_10 | hal.GPIO_Pin_11 | hal.GPIO_Pin_12;
    gpio.GPIO_Mode = hal.GPIO_Mode_Out_PP;
    gpio.GPIO_Speed = hal.GPIO_Speed_50MHz;
    hal.GPIO_Init(hal.GPIOB, &gpio);

    gpio.GPIO_Pin = hal.GPIO_Pin_13;
    gpio.GPIO_Mode = hal.GPIO_Mode_AF_PP;
    gpio.GPIO_Speed = hal.GPIO_Speed_50MHz;
    hal.GPIO_Init(hal.GPIOB, &gpio);

    gpio.GPIO_Pin = hal.GPIO_Pin_14;
    gpio.GPIO_Mode = hal.GPIO_Mode_IN_FLOATING;
    hal.GPIO_Init(hal.GPIOB, &gpio);

    gpio.GPIO_Pin = hal.GPIO_Pin_15;
    gpio.GPIO_Mode = hal.GPIO_Mode_AF_PP;
    gpio.GPIO_Speed = hal.GPIO_Speed_50MHz;
    hal.GPIO_Init(hal.GPIOB, &gpio);

    spi.SPI_Direction = hal.SPI_Direction_1Line_Tx;
    spi.SPI_Mode = hal.SPI_Mode_Master;
    spi.SPI_DataSize = hal.SPI_DataSize_8b;
    spi.SPI_CPOL = hal.SPI_CPOL_High;
    spi.SPI_CPHA = hal.SPI_CPHA_2Edge;
    spi.SPI_NSS = hal.SPI_NSS_Soft;
    spi.SPI_BaudRatePrescaler = hal.SPI_BaudRatePrescaler_2;
    spi.SPI_FirstBit = hal.SPI_FirstBit_MSB;
    spi.SPI_CRCPolynomial = 7;
    hal.SPI_Init(hal.SPI2, &spi);
    hal.SPI_Cmd(hal.SPI2, hal.ENABLE);
}

pub var dma_tc_flag: i32 = 0;

fn dmaTcCount() i32 {
    return @as(*volatile i32, &dma_tc_flag).*;
}

fn waitDmaTc(prev_count: i32) void {
    while (dmaTcCount() == prev_count) {}
}

fn dma1Channel5IRQHandler() callconv(.c) void {
    if (hal.DMA_GetITStatus(hal.DMA1_IT_TC5) != hal.RESET) {
        hal.DMA_ClearITPendingBit(hal.DMA1_IT_GL5);
        @as(*volatile i32, &dma_tc_flag).* += 1;
    }
}

comptime {
    @export(&dma1Channel5IRQHandler, .{ .name = "DMA1_Channel5_IRQHandler", .linkage = .strong });
}

fn initDma() void {
    hal.RCC_AHBPeriphClockCmd(hal.RCC_AHBPeriph_DMA1, hal.ENABLE);

    var dma: hal.DMA_InitTypeDef = undefined;
    hal.DMA_StructInit(&dma);
    dma.DMA_PeripheralBaseAddr = @intFromPtr(&hal.SPI2.*.DATAR);
    dma.DMA_MemoryBaseAddr = 0;
    dma.DMA_DIR = hal.DMA_DIR_PeripheralDST;
    dma.DMA_BufferSize = 0;
    dma.DMA_PeripheralInc = hal.DMA_PeripheralInc_Disable;
    dma.DMA_MemoryInc = hal.DMA_MemoryInc_Enable;
    dma.DMA_PeripheralDataSize = hal.DMA_PeripheralDataSize_HalfWord;
    dma.DMA_MemoryDataSize = hal.DMA_MemoryDataSize_HalfWord;
    dma.DMA_Mode = hal.DMA_Mode_Normal;
    dma.DMA_Priority = hal.DMA_Priority_High;
    dma.DMA_M2M = hal.DMA_M2M_Disable;

    hal.DMA_Init(hal.DMA1_Channel5, &dma);

    // Enable DMA1 Channel5 Transfer Complete interrupt
    hal.DMA_ITConfig(hal.DMA1_Channel5, hal.DMA_IT_TC, hal.ENABLE);

    var nvic: hal.NVIC_InitTypeDef = undefined;
    nvic.NVIC_IRQChannel = hal.DMA1_Channel5_IRQn;
    nvic.NVIC_IRQChannelPreemptionPriority = 1;
    nvic.NVIC_IRQChannelSubPriority = 0;
    nvic.NVIC_IRQChannelCmd = hal.ENABLE;
    hal.NVIC_Init(&nvic);

    hal.SPI_I2S_DMACmd(hal.SPI2, hal.SPI_I2S_DMAReq_Tx, hal.ENABLE);
}

pub fn init() void {
    const Entry = struct { cmd: u8, data: []const u8 };
    const madctl = switch (USE_HORIZONTAL) {
        0 => 0x00,
        1 => 0xC0,
        2 => 0x70,
        else => 0xA0,
    };

    const seq = comptime [_]Entry{
        .{ .cmd = 0x36, .data = &.{madctl} },
        .{ .cmd = 0x3A, .data = &.{0x05} },
        .{ .cmd = 0xB2, .data = &.{ 0x0C, 0x0C, 0x00, 0x33, 0x33 } },
        .{ .cmd = 0xB7, .data = &.{0x35} },
        .{ .cmd = 0xBB, .data = &.{0x32} },
        .{ .cmd = 0xC2, .data = &.{0x01} },
        .{ .cmd = 0xC3, .data = &.{0x15} },
        .{ .cmd = 0xC4, .data = &.{0x20} },
        .{ .cmd = 0xC6, .data = &.{0x0F} },
        .{ .cmd = 0xD0, .data = &.{ 0xA4, 0xA1 } },
        .{ .cmd = 0xE0, .data = &.{ 0xD0, 0x08, 0x0E, 0x09, 0x09, 0x05, 0x31, 0x33, 0x48, 0x17, 0x14, 0x15, 0x31, 0x34 } },
        .{ .cmd = 0xE1, .data = &.{ 0xD0, 0x08, 0x0E, 0x09, 0x09, 0x15, 0x31, 0x33, 0x48, 0x17, 0x14, 0x15, 0x31, 0x34 } },
        .{ .cmd = 0x21, .data = &.{} },
        .{ .cmd = 0x29, .data = &.{} },
    };

    initGpio();
    initDma();

    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_11, hal.Bit_SET);
    c.Delay_Ms(100);
    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_9, hal.Bit_SET);
    c.Delay_Ms(100);

    writeReg(0x11);
    c.Delay_Ms(120);

    inline for (seq) |e| {
        writeReg(e.cmd);
        inline for (e.data) |d| {
            writeData8(d);
        }
    }
}

// ── C-compatible exports ─────────────────────────────────────────

pub export fn lcd_init() void {
    init();
}

pub export fn LCD_SetBrightness(brightness: u8) void {
    setBrightness(brightness);
}

pub export fn lcd_flush_pixels(x1: u16, y1: u16, x2: u16, y2: u16, pixels: [*]const u16) void {
    flushPixels(x1, y1, x2, y2, pixels);
}

pub export fn lcd_write_pixels(pixels: [*]const u16, count: u32) void {
    writePixels(pixels, count);
}

pub export fn lcd_address_set(x1: u16, y1: u16, x2: u16, y2: u16) void {
    addressSet(x1, y1, x2, y2);
}

pub export fn lcd_set_color(back: u16, fore: u16) void {
    back_color = back;
    fore_color = fore;
}

pub export fn lcd_clear(color: u16) void {
    fill(0, 0, WIDTH, HEIGHT, color);
}

pub export fn lcd_draw_point(x: u16, y: u16) void {
    drawPoint(x, y);
}

pub export fn lcd_draw_point_color(x: u16, y: u16, color: u16) void {
    drawPointColor(x, y, color);
}

pub export fn lcd_draw_line(x1: u16, y1: u16, x2: u16, y2: u16) void {
    drawLine(x1, y1, x2, y2);
}

pub export fn lcd_draw_rectangle(x1: u16, y1: u16, x2: u16, y2: u16) void {
    drawRectangle(x1, y1, x2, y2);
}

pub export fn lcd_draw_circle(x0: u16, y0: u16, r: u8) void {
    drawCircle(x0, y0, r);
}

pub export fn lcd_fill(xsta: u16, ysta: u16, xend: u16, yend: u16, color: u16) void {
    fill(xsta, ysta, xend, yend, color);
}

pub export fn lcd_show_num(x: u16, y: u16, num: u32, len: u8, size: u32) void {
    showNum(x, y, num, len, size);
}

pub export fn lcd_show_string(x: u16, y: u16, size: u32, str: [*:0]const u8) void {
    showString(x, y, size, std.mem.sliceTo(str, 0));
}

pub export fn lcd_show_image(x: u16, y: u16, length: u16, wide: u16, data: [*]const u8) void {
    showImage(x, y, length, wide, data);
}

pub export fn lcd_display_on() void {
    displayOn();
}

pub export fn lcd_display_off() void {
    displayOff();
}

pub export fn lcd_enter_sleep() void {
    enterSleep();
}

pub export fn lcd_exit_sleep() void {
    exitSleep();
}
