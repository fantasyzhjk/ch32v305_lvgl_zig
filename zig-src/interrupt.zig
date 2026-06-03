const std = @import("std");

pub fn exportFastIrq(
    comptime irq_name: []const u8,
    comptime body: fn () callconv(.c) void,
) void {
    const body_name = std.fmt.comptimePrint("__zig_irq_body_{s}", .{irq_name});

    const Wrapper = struct {
        fn handler() callconv(.naked) noreturn {
            asm volatile (
                \\ addi sp, sp, -16
                \\ sw ra, 12(sp)
                \\ call 
                ++ body_name ++
                \\
                \\ lw ra, 12(sp)
                \\ addi sp, sp, 16
                \\ mret
            );
        }
    };

    @export(&body, .{ .name = body_name, .linkage = .strong });
    @export(&Wrapper.handler, .{ .name = irq_name, .linkage = .strong });
}
