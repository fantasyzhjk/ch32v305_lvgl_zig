pub const Color = struct {
    value: u16, // Hardware format (RGB565)

    pub const WHITE = Color{ .value = 0xFFFF };
    pub const BLACK = Color{ .value = 0x0000 };
    pub const BLUE = Color{ .value = 0x001F };
    pub const RED = Color{ .value = 0xF800 };
    pub const MAGENTA = Color{ .value = 0xF81F };
    pub const GREEN = Color{ .value = 0x07E0 };
    pub const CYAN = Color{ .value = 0x7FFF };
    pub const YELLOW = Color{ .value = 0xFFE0 };
    pub const LGRAY = Color{ .value = 0xC618 };
    pub const DARKGRAY = Color{ .value = 0x4208 };
    pub const PURPLE = Color{ .value = 0x8010 };
    pub const GOLD = Color{ .value = 0xFEA0 };

    /// Create Color from 8-bit RGB
    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return .{
            .value = (@as(u16, r & 0xF8) << 8) | (@as(u16, g & 0xFC) << 3) | (@as(u16, b) >> 3),
        };
    }

    /// Return raw RGB565 for hardware
    pub fn toRgb565(self: Color) u16 {
        return self.value;
    }
};
