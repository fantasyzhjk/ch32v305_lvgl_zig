const std = @import("std");
const platform = @import("platform.zig");

pub fn exportFastIrq(
    comptime irq_name: []const u8,
    comptime impl: fn () callconv(.c) void,
) void {
    if (platform.is_embedded) {
        const impl_name = std.fmt.comptimePrint("__zig_irq_impl_{s}", .{irq_name});

        const Wrapper = struct {
            fn handler() callconv(.naked) noreturn {
                asm volatile ("call " ++ impl_name ++ "\n" ++ "mret");
            }
        };

        @export(&impl, .{ .name = impl_name, .linkage = .strong });
        @export(&Wrapper.handler, .{ .name = irq_name, .linkage = .strong });
    } else {
        // No-op for native simulation
    }
}
