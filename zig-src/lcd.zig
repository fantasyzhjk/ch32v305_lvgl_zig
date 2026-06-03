pub const lcd = @cImport({
    @cInclude("lcd.h");
    @cInclude("lv_examples.h");
    @cInclude("lv_port_disp.h");
});
