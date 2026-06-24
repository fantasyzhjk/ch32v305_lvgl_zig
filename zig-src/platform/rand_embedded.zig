const hal = @import("../ch32.zig").hal;

pub fn randRange(min: i32, max: i32) i32 {
    const r = hal.RNG_GetRandomNumber();
    return min + @as(i32, @intCast(r % @as(u32, @intCast(max - min + 1))));
}
