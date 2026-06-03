pub const lcd = @cImport({
    @cInclude("lcd.h");
    @cInclude("lv_examples.h");
    @cInclude("porting/lv_port_disp.h");
});
