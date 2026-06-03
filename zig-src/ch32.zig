pub const hal = @cImport({
    @cInclude("ch32v30x.h");
});

pub const c = @cImport({
    @cInclude("debug.h");
    @cInclude("nanoprintf.h");
    @cInclude("stdio.h");
});

pub const lcd = @cImport({
    @cInclude("lcd.h");
    @cInclude("lv_examples.h");
});
