const std = @import("std");
const ui = @import("../ui.zig");
const Color = ui.Color565;

pub fn optionalColorData(color: ?Color) ?u16 {
    return if (color) |c| c.data else null;
}

pub fn requiredOption(comptime T: type, args: anytype, comptime name: []const u8) T {
    const Args = @TypeOf(args);
    if (!@hasField(Args, name)) {
        @compileError("missing required UI option: " ++ name);
    }
    return @field(args, name);
}

pub fn option(comptime T: type, args: anytype, comptime name: []const u8, default: T) T {
    const Args = @TypeOf(args);
    if (@hasField(Args, name)) {
        return @field(args, name);
    }
    return default;
}

pub const Container = @import("container.zig").Container;
pub const Line = @import("line.zig").Line;
pub const Label = @import("label.zig").Label;
pub const MarqueeLabel = @import("marquee_label.zig").MarqueeLabel;
pub const Panel = @import("panel.zig").Panel;
pub const Image = @import("image.zig").Image;
pub const Button = @import("button.zig").Button;
pub const List = @import("list.zig").List;
