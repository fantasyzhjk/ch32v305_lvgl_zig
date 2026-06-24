const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

pub fn init() void {}

pub inline fn millis() u32 {
    return c.SDL_GetTicks();
}
