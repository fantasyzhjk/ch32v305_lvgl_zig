//! Minimal HAL stub for native builds.
//! Only needs to compile — none of these are actually called at runtime.

pub const ENABLE: u32 = 1;
pub const DISABLE: u32 = 0;
pub const SET: u32 = 1;
pub const RESET: u32 = 0;

pub const SystemCoreClock: u32 = 144_000_000;
pub const NVIC_PriorityGroup_2: u32 = 0;

// Catch-all no-op for any HAL function that gets referenced in dead code
fn stub0() callconv(.c) u32 { return 0; }
fn stub1(_: anytype) callconv(.c) void {}
fn stub2(_: anytype, _: anytype) callconv(.c) void {}
fn stub3(_: anytype, _: anytype, _: anytype) callconv(.c) void {}

// GPIO stubs for LED control
pub const GPIOA = @as(*volatile anyopaque, undefined);
pub const GPIO_Pin_3: u32 = 1 << 3;
pub const Bit_SET: u32 = 1;
pub const Bit_RESET: u32 = 0;
pub fn GPIO_WriteBit(_: anytype, _: anytype, _: anytype) void {}

// Type stubs for @cImport compatibility
pub const GPIO_InitTypeDef = extern struct { GPIO_Pin: u32 = 0, GPIO_Speed: u32 = 0, GPIO_Mode: u32 = 0 };
pub const SPI_InitTypeDef = extern struct { SPI_Direction: u32 = 0, SPI_Mode: u32 = 0, SPI_DataSize: u32 = 0, SPI_CPOL: u32 = 0, SPI_CPHA: u32 = 0, SPI_NSS: u32 = 0, SPI_BaudRatePrescaler: u32 = 0, SPI_FirstBit: u32 = 0, SPI_CRCPolynomial: u32 = 0 };
pub const TIM_TimeBaseInitTypeDef = extern struct { TIM_Prescaler: u16 = 0, TIM_CounterMode: u16 = 0, TIM_Period: u32 = 0, TIM_ClockDivision: u16 = 0, TIM_RepetitionCounter: u16 = 0 };
pub const DMA_InitTypeDef = extern struct { DMA_PeripheralBaseAddr: u32 = 0, DMA_MemoryBaseAddr: u32 = 0, DMA_DIR: u32 = 0, DMA_BufferSize: u32 = 0, DMA_PeripheralInc: u32 = 0, DMA_MemoryInc: u32 = 0, DMA_PeripheralDataSize: u32 = 0, DMA_MemoryDataSize: u32 = 0, DMA_Mode: u32 = 0, DMA_Priority: u32 = 0, DMA_M2M: u32 = 0 };
pub const NVIC_InitTypeDef = extern struct { NVIC_IRQChannel: u32 = 0, NVIC_IRQChannelPreemptionPriority: u32 = 0, NVIC_IRQChannelSubPriority: u32 = 0, NVIC_IRQChannelCmd: u32 = 0 };
