pub fn ColorT(comptime Format: type) type {
    return struct {
        const Self = @This();

        data: Format,

        pub const Rgb565 = u16;
        pub const Rgb888 = struct { r: u8, g: u8, b: u8 };

        pub const WHITE = fromRgb(0xFF, 0xFF, 0xFF);
        pub const BLACK = fromRgb(0x00, 0x00, 0x00);
        pub const RED = fromRgb(0xFF, 0x00, 0x00);
        pub const GREEN = fromRgb(0x00, 0xFF, 0x00);
        pub const BLUE = fromRgb(0x00, 0x00, 0xFF);
        pub const MAGENTA = fromRgb(0xFF, 0x00, 0xFF);
        pub const CYAN = fromRgb(0x00, 0xFF, 0xFF);
        pub const YELLOW = fromRgb(0xFF, 0xFF, 0x00);
        pub const LGRAY = fromRgb(0xC6, 0xC3, 0xC6);
        pub const DARKGRAY = fromRgb(0x42, 0x41, 0x42);
        pub const PURPLE = fromRgb(0x80, 0x00, 0x80);
        pub const GOLD = fromRgb(0xFF, 0xD7, 0x00);

        pub fn fromRgb(r: u8, g: u8, b: u8) Self {
            if (Format == Rgb565) {
                return .{ .data = (@as(u16, r & 0xF8) << 8) |
                    (@as(u16, g & 0xFC) << 3) |
                    (@as(u16, b) >> 3) };
            } else if (Format == Rgb888) {
                return .{ .data = .{ .r = r, .g = g, .b = b } };
            } else {
                @compileError("Unsupported color format: " ++ @typeName(Format));
            }
        }

        pub fn toRgb565(self: Self) u16 {
            if (Format == Rgb565) {
                return self.data;
            } else if (Format == Rgb888) {
                return (@as(u16, self.data.r & 0xF8) << 8) |
                    (@as(u16, self.data.g & 0xFC) << 3) |
                    (@as(u16, self.data.b) >> 3);
            } else {
                @compileError("Unsupported color format: " ++ @typeName(Format));
            }
        }

        pub fn toRgb888(self: Self) Rgb888 {
            if (Format == Rgb888) {
                return self.data;
            } else if (Format == Rgb565) {
                const r5 = @as(u8, @truncate((self.data >> 11) & 0x1F));
                const g6 = @as(u8, @truncate((self.data >> 5) & 0x3F));
                const b5 = @as(u8, @truncate(self.data & 0x1F));
                return .{
                    .r = (r5 << 3) | (r5 >> 2),
                    .g = (g6 << 2) | (g6 >> 4),
                    .b = (b5 << 3) | (b5 >> 2),
                };
            } else {
                @compileError("Unsupported color format: " ++ @typeName(Format));
            }
        }

        /// 转换到另一种格式
        pub fn convert(self: Self, comptime TargetFormat: type) ColorT(TargetFormat) {
            const rgb = self.toRgb888();
            return ColorT(TargetFormat).fromRgb(rgb.r, rgb.g, rgb.b);
        }
    };
}

// 具体类型别名
pub const Color565 = ColorT(u16);
pub const Color888 = ColorT(struct { r: u8, g: u8, b: u8 });
