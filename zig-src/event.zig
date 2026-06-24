/// Event system — transparent input abstraction.
/// Embedded: USB serial "Y<yaw>,P<pitch>" → RotationEvent
/// Native:   SDL keyboard arrows → RotationEvent
const platform = @import("platform.zig");
const impl = if (platform.is_embedded) @import("platform/event_embedded.zig") else @import("platform/event_native.zig");

pub const Event = union(enum) {
    rotation: Rotation,
    quit,
    none,
};

pub const Rotation = struct {
    yaw: f32,
    pitch: f32,
};

pub const poll = impl.poll;
