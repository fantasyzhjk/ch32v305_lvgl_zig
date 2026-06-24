const platform = @import("platform.zig");
const impl = if (platform.is_embedded) @import("platform/tick_embedded.zig") else @import("platform/tick_native.zig");

pub const system_ticks = impl.system_ticks;
pub const init = impl.init;
pub const millis = impl.millis;
