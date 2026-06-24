const std = @import("std");
const ch32 = @import("../ch32.zig");
const hal = ch32.hal;
const c = ch32.c;
const font = @import("../ui/font.zig");
const interrupt = @import("../interrupt.zig");

pub const WIDTH: u16 = 240;
pub const HEIGHT: u16 = 240;

const USE_HORIZONTAL: comptime_int = 0;

pub const Color = @import("../ui/color.zig").Color565;

pub var back_color: u16 = Color.BLACK.toRgb565();
pub var fore_color: u16 = Color.WHITE.toRgb565();

pub var dma_tc_flag: bool = true;
pub var dma_tc_counter: u32 = 0;
pub var dma_auto_cleanup: bool = false;
var initialized: bool = false;

comptime {
    interrupt.exportFastIrq("DMA1_Channel5_IRQHandler", struct {
        fn impl() callconv(.c) void {
            if (hal.DMA_GetITStatus(hal.DMA1_IT_TC5) != hal.RESET) {
                hal.DMA_ClearITPendingBit(hal.DMA1_IT_GL5);

                if (@as(*volatile bool, &dma_auto_cleanup).*) {
                    // Wait for SPI to finish shifting the last word
                    while (hal.SPI_I2S_GetFlagStatus(hal.SPI2, hal.SPI_I2S_FLAG_BSY) == hal.SET) {}
                    // Set CS High
                    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_12, hal.Bit_SET);

                    // Restore 8-bit mode transparently
                    hal.SPI_Cmd(hal.SPI2, hal.DISABLE);
                    hal.SPI_DataSizeConfig(hal.SPI2, hal.SPI_DataSize_8b);
                    hal.SPI_Cmd(hal.SPI2, hal.ENABLE);

                    @as(*volatile bool, &dma_auto_cleanup).* = false;
                }

                @as(*volatile bool, &dma_tc_flag).* = true;
                @as(*volatile u32, &dma_tc_counter).* +%= 1;
            }
        }
    }.impl);
}

fn spiWaitBusIdle() void {
    while (hal.SPI_I2S_GetFlagStatus(hal.SPI2, hal.SPI_I2S_FLAG_BSY) == hal.SET) {}
}

fn spiWaitTx() void {
    while (hal.SPI_I2S_GetFlagStatus(hal.SPI2, hal.SPI_I2S_FLAG_TXE) == hal.RESET) {}
}

fn disableInterrupts() void {
    const mask: usize = 0x88;
    asm volatile (
        \\csrc 0x800, %[mask]
        \\fence.i
        :
        : [mask] "r" (mask),
        : .{ .memory = true });
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

/// Wait for previous DMA transfer and IRQ cleanup to finish
pub fn waitDmaDone() void {
    while (!@as(*volatile bool, &dma_tc_flag).*) {}
}

pub fn fill(xsta: u16, ysta: u16, xend: u16, yend: u16, color: u16) void {
    waitDmaDone();

    addressSet(xsta, ysta, xend - 1, yend - 1);
    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_12, hal.Bit_RESET);

    const count: u32 = @as(u32, xend - xsta) * @as(u32, yend - ysta);

    // Switch to 16-bit
    hal.SPI_Cmd(hal.SPI2, hal.DISABLE);
    hal.SPI_DataSizeConfig(hal.SPI2, hal.SPI_DataSize_16b);
    hal.SPI_Cmd(hal.SPI2, hal.ENABLE);

    var remaining = count;
    while (remaining > 0) {
        const chunk_size: u16 = if (remaining > 65535) 65535 else @intCast(remaining);

        @as(*volatile bool, &dma_tc_flag).* = false;
        // Last chunk should trigger auto-cleanup in IRQ
        @as(*volatile bool, &dma_auto_cleanup).* = (remaining <= chunk_size);

        hal.DMA_Cmd(hal.DMA1_Channel5, hal.DISABLE);
        while ((hal.DMA1_Channel5.*.CFGR & 1) != 0) {}
        hal.DMA_ClearITPendingBit(hal.DMA1_IT_GL5);

        hal.DMA1_Channel5.*.CFGR &= ~hal.DMA_MemoryInc_Enable;
        hal.DMA1_Channel5.*.MADDR = @intFromPtr(&color);
        hal.DMA1_Channel5.*.CNTR = chunk_size;

        hal.DMA_Cmd(hal.DMA1_Channel5, hal.ENABLE);

        remaining -= chunk_size;
        // fill always waits to be simple
        waitDmaDone();
    }

    // Restore MINC for flushAsync (fill disables it to repeat same color)
    hal.DMA_Cmd(hal.DMA1_Channel5, hal.DISABLE);
    hal.DMA1_Channel5.*.CFGR |= hal.DMA_MemoryInc_Enable;
}

pub fn flushAsync(x1: u16, y1: u16, x2: u16, y2: u16, pixels: [*]const u16) void {
    const count: u32 = @as(u32, x2 - x1 + 1) * @as(u32, y2 - y1 + 1);
    addressSet(x1, y1, x2, y2);

    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_12, hal.Bit_RESET);

    hal.SPI_Cmd(hal.SPI2, hal.DISABLE);
    hal.SPI_DataSizeConfig(hal.SPI2, hal.SPI_DataSize_16b);
    hal.SPI_Cmd(hal.SPI2, hal.ENABLE);

    @as(*volatile bool, &dma_tc_flag).* = false;
    @as(*volatile bool, &dma_auto_cleanup).* = true;

    hal.DMA_Cmd(hal.DMA1_Channel5, hal.DISABLE);
    while ((hal.DMA1_Channel5.*.CFGR & 1) != 0) {}
    hal.DMA_ClearITPendingBit(hal.DMA1_IT_GL5);

    hal.DMA1_Channel5.*.CFGR |= hal.DMA_MemoryInc_Enable;
    hal.DMA1_Channel5.*.MADDR = @intFromPtr(pixels);
    hal.DMA1_Channel5.*.CNTR = count;
    hal.DMA_Cmd(hal.DMA1_Channel5, hal.ENABLE);
}

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

    gpio.GPIO_Pin = hal.GPIO_Pin_9 | hal.GPIO_Pin_10 | hal.GPIO_Pin_11 | hal.GPIO_Pin_12;
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
    hal.DMA_ITConfig(hal.DMA1_Channel5, hal.DMA_IT_TC, hal.ENABLE);

    var nvic: hal.NVIC_InitTypeDef = undefined;
    nvic.NVIC_IRQChannel = hal.DMA1_Channel5_IRQn;
    nvic.NVIC_IRQChannelPreemptionPriority = 1;
    nvic.NVIC_IRQChannelSubPriority = 0;
    nvic.NVIC_IRQChannelCmd = hal.ENABLE;
    hal.NVIC_Init(&nvic);

    hal.SPI_I2S_DMACmd(hal.SPI2, hal.SPI_I2S_DMAReq_Tx, hal.ENABLE);

    dma_tc_flag = true;
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

    // 电源稳定延时（USB 插拔时电源/HSE 晶振需要时间）
    c.Delay_Ms(200);

    // 背光打开
    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_11, hal.Bit_SET);
    c.Delay_Ms(100);

    // 复位释放（GPIO 默认低电平，RST 已处于复位状态，拉高即释放）
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

    initialized = true;
}

pub fn deinit() void {
    initialized = false;
    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_11, hal.Bit_RESET);
}

pub fn present() void {}

/// Enter a self-contained LCD mode suitable for panic handling. Interrupts are
/// disabled and any in-flight DMA transfer is abandoned before SPI is restored
/// to the 8-bit command mode expected by addressSet().
pub fn panicBegin() bool {
    if (!initialized) return false;

    disableInterrupts();
    hal.DMA_Cmd(hal.DMA1_Channel5, hal.DISABLE);
    while ((hal.DMA1_Channel5.*.CFGR & 1) != 0) {}
    hal.SPI_I2S_DMACmd(hal.SPI2, hal.SPI_I2S_DMAReq_Tx, hal.DISABLE);
    hal.DMA_ClearITPendingBit(hal.DMA1_IT_GL5);

    spiWaitBusIdle();
    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_12, hal.Bit_SET);

    hal.SPI_Cmd(hal.SPI2, hal.DISABLE);
    hal.SPI_DataSizeConfig(hal.SPI2, hal.SPI_DataSize_8b);
    hal.SPI_Cmd(hal.SPI2, hal.ENABLE);

    dma_tc_flag = true;
    dma_auto_cleanup = false;
    return true;
}

/// Blocking RGB565 rectangle fill used only after panicBegin().
pub fn panicFill(x: u16, y: u16, w: u16, h: u16, color: u16) void {
    if (w == 0 or h == 0) return;

    addressSet(x, y, x + w - 1, y + h - 1);
    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_12, hal.Bit_RESET);

    hal.SPI_Cmd(hal.SPI2, hal.DISABLE);
    hal.SPI_DataSizeConfig(hal.SPI2, hal.SPI_DataSize_16b);
    hal.SPI_Cmd(hal.SPI2, hal.ENABLE);

    var remaining: u32 = @as(u32, w) * @as(u32, h);
    while (remaining != 0) : (remaining -= 1) {
        spiWaitTx();
        hal.SPI_I2S_SendData(hal.SPI2, color);
    }

    spiWaitBusIdle();
    hal.GPIO_WriteBit(hal.GPIOB, hal.GPIO_Pin_12, hal.Bit_SET);

    hal.SPI_Cmd(hal.SPI2, hal.DISABLE);
    hal.SPI_DataSizeConfig(hal.SPI2, hal.SPI_DataSize_8b);
    hal.SPI_Cmd(hal.SPI2, hal.ENABLE);
}

pub fn panicPresent() void {}

pub fn panicHalt() noreturn {
    disableInterrupts();
    while (true) asm volatile ("wfi");
}
