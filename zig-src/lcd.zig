/// Transparent LCD compatibility layer.
const platform = @import("platform.zig");
const _impl = if (platform.is_embedded) @import("platform/lcd_embedded.zig") else @import("platform/lcd_native.zig");

pub const WIDTH = _impl.WIDTH;
pub const HEIGHT = _impl.HEIGHT;
pub const Color = _impl.Color;
pub const impl = _impl;

pub const init = _impl.init;
pub const deinit = _impl.deinit;
pub const fill = _impl.fill;
pub const flushAsync = _impl.flushAsync;
pub const waitDmaDone = _impl.waitDmaDone;
pub const addressSet = _impl.addressSet;
pub const present = _impl.present;
