/// Native event source: SDL mouse motion → RotationEvent
/// Mirrors mouse_ctrl.py behavior: mouse dx/dy → yaw/pitch deltas
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const Event = @import("../event.zig").Event;
const Rotation = @import("../event.zig").Rotation;

const sensitivity: f32 = 0.3;

var paused: bool = false;

pub fn poll() Event {
    var event: c.SDL_Event = undefined;
    var acc_yaw: f32 = 0;
    var acc_pitch: f32 = 0;
    var has_rotation = false;

    while (c.SDL_PollEvent(&event) != 0) {
        switch (event.type) {
            c.SDL_QUIT => return .quit,
            c.SDL_KEYDOWN => {
                if (event.key.keysym.sym == c.SDLK_ESCAPE) return .quit;
            },
            c.SDL_MOUSEBUTTONDOWN => {
                if (event.button.button == c.SDL_BUTTON_LEFT) paused = true;
            },
            c.SDL_MOUSEBUTTONUP => {
                if (event.button.button == c.SDL_BUTTON_LEFT) paused = false;
            },
            c.SDL_MOUSEMOTION => {
                if (!paused) {
                    acc_yaw += @as(f32, @floatFromInt(event.motion.xrel)) * sensitivity;
                    acc_pitch += @as(f32, @floatFromInt(event.motion.yrel)) * sensitivity;
                    has_rotation = true;
                }
            },
            else => {},
        }
    }

    if (has_rotation) return .{ .rotation = .{ .yaw = acc_yaw, .pitch = acc_pitch } };
    return .none;
}
