//! SDL2-based LCD simulation backend.
//! Provides the same public API as lcd_embedded.zig but renders to an SDL2 window.

const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const color_mod = @import("../ui/color.zig");

pub const WIDTH: u16 = 240;
pub const HEIGHT: u16 = 240;
pub const Color = color_mod.Color565;

const SCALE: u32 = 3;
const WIN_WIDTH: u32 = WIDTH * SCALE;
const WIN_HEIGHT: u32 = HEIGHT * SCALE;

var window: ?*c.SDL_Window = null;
var renderer: ?*c.SDL_Renderer = null;
var texture: ?*c.SDL_Texture = null;

var fb: [WIDTH * HEIGHT]u16 = undefined;

pub var dma_tc_flag: bool = true;
pub var dma_tc_counter: u32 = 0;

pub fn init() void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        @panic("SDL_Init failed");
    }

    window = c.SDL_CreateWindow(
        "LCD Simulator - 240x240",
        c.SDL_WINDOWPOS_CENTERED,
        c.SDL_WINDOWPOS_CENTERED,
        @intCast(WIN_WIDTH),
        @intCast(WIN_HEIGHT),
        c.SDL_WINDOW_SHOWN,
    );

    renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC);

    texture = c.SDL_CreateTexture(
        renderer,
        c.SDL_PIXELFORMAT_RGB565,
        c.SDL_TEXTUREACCESS_STREAMING,
        @intCast(WIDTH),
        @intCast(HEIGHT),
    );

    @memset(&fb, 0);
    _ = c.SDL_SetRelativeMouseMode(c.SDL_TRUE);
    presentImpl();
}

pub fn deinit() void {
    if (texture) |t| c.SDL_DestroyTexture(t);
    if (renderer) |r| c.SDL_DestroyRenderer(r);
    if (window) |w| c.SDL_DestroyWindow(w);
    c.SDL_Quit();
}

pub fn present() void {
    presentImpl();
}

pub fn addressSet(_: u16, _: u16, _: u16, _: u16) void {}

pub fn fill(xsta: u16, ysta: u16, xend: u16, yend: u16, color: u16) void {
    var y = ysta;
    while (y < yend) : (y += 1) {
        var x = xsta;
        while (x < xend) : (x += 1) {
            fb[@as(usize, y) * WIDTH + x] = color;
        }
    }
}

pub fn flushAsync(x1: u16, y1: u16, x2: u16, y2: u16, pixels: [*]const u16) void {
    const w: usize = @intCast(x2 - x1 + 1);
    const h: usize = @intCast(y2 - y1 + 1);

    var row: usize = 0;
    while (row < h) : (row += 1) {
        const dst_y = y1 + row;
        const dst_start: usize = @as(usize, dst_y) * WIDTH + x1;
        const src_start: usize = row * w;
        @memcpy(fb[dst_start .. dst_start + w], pixels[src_start .. src_start + w]);
    }

    dma_tc_counter +%= 1;
    dma_tc_flag = true;
}

pub fn waitDmaDone() void {
    dma_tc_flag = true;
}

fn presentImpl() void {
    _ = c.SDL_UpdateTexture(texture, null, @ptrCast(&fb), @intCast(WIDTH * 2));
    _ = c.SDL_RenderClear(renderer);
    _ = c.SDL_RenderCopy(renderer, texture, null, null);
    c.SDL_RenderPresent(renderer);
}
