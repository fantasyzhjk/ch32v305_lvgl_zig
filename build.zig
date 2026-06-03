const std = @import("std");
const deps = @import("deps/build.zig");

const peripheral_sources = [_][]const u8{
    "hal/Peripheral/src/ch32v30x_adc.c",
    "hal/Peripheral/src/ch32v30x_bkp.c",
    "hal/Peripheral/src/ch32v30x_can.c",
    "hal/Peripheral/src/ch32v30x_crc.c",
    "hal/Peripheral/src/ch32v30x_dac.c",
    "hal/Peripheral/src/ch32v30x_dbgmcu.c",
    "hal/Peripheral/src/ch32v30x_dma.c",
    "hal/Peripheral/src/ch32v30x_exti.c",
    "hal/Peripheral/src/ch32v30x_flash.c",
    "hal/Peripheral/src/ch32v30x_gpio.c",
    "hal/Peripheral/src/ch32v30x_i2c.c",
    "hal/Peripheral/src/ch32v30x_iwdg.c",
    "hal/Peripheral/src/ch32v30x_misc.c",
    "hal/Peripheral/src/ch32v30x_opa.c",
    "hal/Peripheral/src/ch32v30x_pwr.c",
    "hal/Peripheral/src/ch32v30x_rcc.c",
    "hal/Peripheral/src/ch32v30x_rtc.c",
    "hal/Peripheral/src/ch32v30x_spi.c",
    "hal/Peripheral/src/ch32v30x_tim.c",
    "hal/Peripheral/src/ch32v30x_usart.c",
    "hal/Peripheral/src/ch32v30x_wwdg.c",
};

const c_sources = [_][]const u8{
    "hal/Core/core_riscv.c",
    "hal/Debug/debug.c",
    "zig-src/c/src/stdio.c",
    "zig-src/c/src/system_ch32v30x.c",
    "zig-src/c/src/ch32v30x_it.c",
    "zig-src/c/src/lcd.c",
};

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(std.Build.parseTargetQuery(.{
        .arch_os_abi = "riscv32-freestanding-none",
        .cpu_features = "generic_rv32+a+c+m+xwchc",
    }) catch @panic("invalid target query"));
    const optimize = .ReleaseSmall;

    const exe = b.addExecutable(.{
        .name = "ch32v30-blink",
        .root_module = b.createModule(.{
            .root_source_file = b.path("zig-src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_lld = true,
    });

    exe.entry = .{ .symbol_name = "_start" };
    exe.link_function_sections = true;
    exe.link_data_sections = true;
    exe.link_gc_sections = true;
    exe.setLinkerScript(b.path("zig-src/c/Link.ld"));

    exe.root_module.addCMacro("ARCH_RISCV", "1");

    exe.root_module.addIncludePath(b.path("hal/Peripheral/inc"));
    exe.root_module.addIncludePath(b.path("hal/Core"));
    exe.root_module.addIncludePath(b.path("hal/Debug"));

    exe.root_module.addIncludePath(b.path("zig-src/c/inc"));

    exe.root_module.addAssemblyFile(b.path("zig-src/c/startup_ch32v30x.S"));
    exe.root_module.addCSourceFiles(.{
        .root = b.path(""),
        .files = &peripheral_sources,
        .flags = &.{
            "-std=gnu99",
            "-Os",
        },
    });

    exe.root_module.addCSourceFiles(.{
        .root = b.path(""),
        .files = &c_sources,
        .flags = &.{
            "-std=gnu99",
            "-Os",
        },
    });

    deps.addLvgl(b, exe);

    exe.root_module.addAnonymousImport("libc", .{
        .root_source_file = b.path("zig-src/libc.zig"),
    });

    const elf_install = b.addInstallBinFile(exe.getEmittedBin(), "ch32v30-blink.elf");
    const bin = b.addObjCopy(exe.getEmittedBin(), .{
        .basename = "ch32v30-blink.bin",
        .format = .bin,
    }).getOutput();
    const bin_install = b.addInstallBinFile(bin, "ch32v30-blink.bin");

    b.getInstallStep().dependOn(&elf_install.step);
    b.getInstallStep().dependOn(&bin_install.step);

    const blink_step = b.step("blink", "Build the CH32V30x GPIOA3 blink image");
    blink_step.dependOn(b.getInstallStep());
}
