const std = @import("std");
const deps = @import("deps/build.zig");
const zcc = @import("compile_commands");

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
    "hal/Peripheral/src/ch32v30x_rng.c",
    "hal/Peripheral/src/ch32v30x_rcc.c",
    "hal/Peripheral/src/ch32v30x_rtc.c",
    "hal/Peripheral/src/ch32v30x_spi.c",
    "hal/Peripheral/src/ch32v30x_tim.c",
    "hal/Peripheral/src/ch32v30x_usart.c",
    "hal/Peripheral/src/ch32v30x_wwdg.c",
    "hal/Core/core_riscv.c",
    "hal/Debug/debug.c",
};

const c_sources = [_][]const u8{
    "zig-src/c/src/usb_descriptors.c",
    "zig-src/c/src/usb_app.c",
    "zig-src/c/src/stdio.c",
    "zig-src/c/src/string.c",
    "zig-src/c/src/ch32v30x_it.c",
    "zig-src/c/src/system_ch32v30x.c",
};

pub fn build(b: *std.Build) void {
    const sim = b.option(bool, "sim", "Build native SDL2 simulation") orelse false;

    const optimize = b.option(std.builtin.OptimizeMode, "optimize", "Optimization mode") orelse .ReleaseSmall;

    if (sim) {
        buildSim(b, optimize);
    } else {
        buildEmbedded(b, optimize);
    }
}

fn buildSim(b: *std.Build, optimize: std.builtin.OptimizeMode) void {
    const target = b.standardTargetOptions(.{});

    const exe = b.addExecutable(.{
        .name = "lcd-sim",
        .root_module = b.createModule(.{
            .root_source_file = b.path("zig-src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // SDL2 setup: use the vendored development libraries (dynamic linking via import lib)
    const sdl2_base = "deps/sdl2/SDL2-2.30.12/x86_64-w64-mingw32";
    exe.root_module.addIncludePath(b.path(sdl2_base ++ "/include"));
    exe.root_module.addObjectFile(b.path(sdl2_base ++ "/lib/libSDL2.dll.a"));
    exe.root_module.link_libc = true;

    // Install SDL2.dll alongside the executable
    const install_dll = b.addInstallBinFile(
        b.path(sdl2_base ++ "/bin/SDL2.dll"),
        "SDL2.dll",
    );
    exe.step.dependOn(&install_dll.step);

    const install = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install.step);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());

    const run_step = b.step("sim", "Run the SDL2 LCD simulation");
    run_step.dependOn(&run.step);
}

fn buildEmbedded(b: *std.Build, optimize: std.builtin.OptimizeMode) void {
    const target = b.resolveTargetQuery(std.Build.parseTargetQuery(.{
        .arch_os_abi = "riscv32-freestanding-none",
        .cpu_features = "generic_rv32+a+c+m+f+xwchc",
    }) catch @panic("invalid target query"));

    const base_c_flags = [_][]const u8{
        "-std=gnu99",
        "-Dasm=__asm__",
        "-ffunction-sections",
        "-fdata-sections",
        "-fno-exceptions",
        "-fno-unwind-tables",
        "-fno-asynchronous-unwind-tables",
    };

    const lto_c_flags = base_c_flags ++ [_][]const u8{
        "-flto",
    };

    const c_flags: []const []const u8 = if (optimize == .Debug)
        &base_c_flags
    else
        &lto_c_flags;

    const exe = b.addExecutable(.{ .name = "ch32v30-demo", .root_module = b.createModule(.{
        .root_source_file = b.path("zig-src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = optimize != .Debug,
    }), .use_lld = true });

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
        .flags = c_flags,
    });

    exe.root_module.addCSourceFiles(.{
        .root = b.path(""),
        .files = &c_sources,
        .flags = c_flags,
    });

    const tusb_lib = deps.addTusb(b, target, optimize, c_flags);
    exe.root_module.linkLibrary(tusb_lib);
    exe.root_module.addIncludePath(b.path("deps/tusb/src"));
    exe.root_module.addIncludePath(b.path("deps/tusb/hw"));
    exe.root_module.addCMacro("CFG_TUSB_MCU", "OPT_MCU_CH32V307");
    exe.root_module.addCMacro("CFG_TUD_WCH_USBIP_USBHS", "1");

    const elf_install = b.addInstallBinFile(
        exe.getEmittedBin(),
        b.fmt("{s}.elf", .{exe.name}),
    );

    const bin = b.addObjCopy(exe.getEmittedBin(), .{
        .basename = b.fmt("{s}.bin", .{exe.name}),
        .format = .bin,
    }).getOutput();

    const bin_install = b.addInstallBinFile(
        bin,
        b.fmt("{s}.bin", .{exe.name}),
    );

    b.getInstallStep().dependOn(&elf_install.step);
    b.getInstallStep().dependOn(&bin_install.step);

    const size_cmd = b.addSystemCommand(&.{
        "rust-size",
        "--format=berkeley",
    });
    size_cmd.addArtifactArg(exe);

    const size_step = b.step("size", "Show ELF size");
    size_step.dependOn(&size_cmd.step);

    const flash_cmd = b.addSystemCommand(&.{ "wchisp", "flash" });
    flash_cmd.addFileArg(bin_install.source);
    flash_cmd.step.dependOn(&size_cmd.step);

    const flash_step = b.step("flash", "Flash the binary to the device using wchisp");
    flash_step.dependOn(&flash_cmd.step);

    const bin_step = b.step("bin", "Build image");
    bin_step.dependOn(b.getInstallStep());

    const targets = b.allocator.alloc(*std.Build.Step.Compile, 1) catch @panic("OOM");
    targets[0] = exe;
    _ = zcc.createStep(b, "cdb", targets);
}
