pub const hal = @cImport({
    @cInclude("ch32v30x.h");
    @cInclude("core_riscv.h");
    @cInclude("ch32v30x_it.h");
});

pub const c = @cImport({
    @cInclude("debug.h");
    @cInclude("nanoprintf.h");
    @cInclude("stdio.h");
});
