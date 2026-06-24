const builtin = @import("builtin");

pub const is_native = builtin.cpu.arch != .riscv32;
pub const is_embedded = !is_native;
