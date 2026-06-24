/// Transparent USB compatibility layer.
/// Embedded: real USB CDC. Native: no-op stubs.
const platform = @import("platform.zig");
const impl = if (platform.is_embedded) @import("platform/usb_embedded.zig") else @import("platform/usb_native.zig");

pub const init = impl.init;
pub const task = impl.task;
pub const write = impl.write;
pub const available = impl.available;
pub const read = impl.read;
pub const readByte = impl.readByte;
