// xorshift32 PRNG for simulation
var state: u32 = 12345;

fn next() u32 {
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    return state;
}

pub fn randRange(min: i32, max: i32) i32 {
    return min + @as(i32, @intCast(next() % @as(u32, @intCast(max - min + 1))));
}
