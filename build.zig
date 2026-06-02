const std = @import("std");

const target = "riscv32-freestanding-none";
const mcpu_arg = "-mcpu=generic_rv32+a+c+m+xwchc";
const zig_optimize = "ReleaseSmall";
const zig_global_cache_dir_name = ".zig-cli-global-cache";

const CObjectOptions = struct {
    basename: []const u8,
    source_path: []const u8,
    bypass_conf_header: bool,
};

pub fn build(b: *std.Build) void {
    const ld_lld = b.findProgram(&.{"ld.lld"}, &.{}) catch
        @panic("ld.lld was not found in PATH");
    const zig_global_cache_dir = b.pathFromRoot(zig_global_cache_dir_name);

    const startup_obj = addAssemblyObject(
        b,
        zig_global_cache_dir,
        "startup_ch32v30x.o",
        "zig-src/startup_ch32v30x.S",
    );
    const system_obj = addCObject(
        b,
        zig_global_cache_dir,
        .{
            .basename = "system_ch32v30x.o",
            .source_path = "zig-src/system_ch32v30x.c",
            .bypass_conf_header = true,
        },
    );
    const gpio_obj = addCObject(
        b,
        zig_global_cache_dir,
        .{
            .basename = "ch32v30x_gpio.o",
            .source_path = "SRC/Peripheral/src/ch32v30x_gpio.c",
            .bypass_conf_header = true,
        },
    );
    const rcc_obj = addCObject(
        b,
        zig_global_cache_dir,
        .{
            .basename = "ch32v30x_rcc.o",
            .source_path = "SRC/Peripheral/src/ch32v30x_rcc.c",
            .bypass_conf_header = true,
        },
    );
    const core_obj = addCObject(
        b,
        zig_global_cache_dir,
        .{
            .basename = "core_riscv.o",
            .source_path = "SRC/Core/core_riscv.c",
            .bypass_conf_header = true,
        },
    );
    const misc_obj = addCObject(
        b,
        zig_global_cache_dir,
        .{
            .basename = "ch32v30x_misc.o",
            .source_path = "SRC/Peripheral/src/ch32v30x_misc.c",
            .bypass_conf_header = true,
        },
    );
    const delay_obj = addCObject(
        b,
        zig_global_cache_dir,
        .{
            .basename = "delay.o",
            .source_path = "zig-src/delay.c",
            .bypass_conf_header = true,
        },
    );
    const main_obj = addZigObject(
        b,
        zig_global_cache_dir,
        "main.o",
        "zig-src/main.zig",
    );

    const link = b.addSystemCommand(&.{ld_lld});
    link.setName("ld.lld ch32v30-blink.elf");
    link.expectExitCode(0);
    link.setCwd(b.path(""));
    link.addArgs(&.{
        "-m",
        "elf32lriscv",
        "--entry=_start",
        "--gc-sections",
        "-static",
    });
    link.addPrefixedFileArg("-T", b.path("zig-src/Link.ld"));
    const map = link.addPrefixedOutputFileArg("-Map=", "ch32v30-blink.map");
    const elf = link.addPrefixedOutputFileArg("-o", "ch32v30-blink.elf");
    link.addFileArg(startup_obj);
    link.addFileArg(system_obj);
    link.addFileArg(gpio_obj);
    link.addFileArg(rcc_obj);
    link.addFileArg(core_obj);
    link.addFileArg(misc_obj);
    link.addFileArg(delay_obj);
    link.addFileArg(main_obj);

    const bin = b.addObjCopy(elf, .{
        .basename = "ch32v30-blink.bin",
        .format = .bin,
    }).getOutput();

    const install_elf = b.addInstallBinFile(elf, "ch32v30-blink.elf");
    const install_bin = b.addInstallBinFile(bin, "ch32v30-blink.bin");
    const install_map = b.addInstallBinFile(map, "ch32v30-blink.map");

    b.getInstallStep().dependOn(&install_elf.step);
    b.getInstallStep().dependOn(&install_bin.step);
    b.getInstallStep().dependOn(&install_map.step);

    const blink_step = b.step("blink", "Build the CH32V30x GPIOA3 blink image");
    blink_step.dependOn(b.getInstallStep());
}

fn addZigCommonArgs(
    run: *std.Build.Step.Run,
    zig_global_cache_dir: []const u8,
) void {
    run.setEnvironmentVariable("ZIG_GLOBAL_CACHE_DIR", zig_global_cache_dir);
    run.addArgs(&.{
        "-target",
        target,
        mcpu_arg,
    });
}

fn addIncludeDirs(run: *std.Build.Step.Run, b: *std.Build) void {
    run.addPrefixedDirectoryArg("-I", b.path("zig-src"));
    run.addPrefixedDirectoryArg("-I", b.path("SRC/Peripheral/inc"));
    run.addPrefixedDirectoryArg("-I", b.path("SRC/Core"));
}

fn addCObject(
    b: *std.Build,
    zig_global_cache_dir: []const u8,
    options: CObjectOptions,
) std.Build.LazyPath {
    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "cc" });
    run.setName(b.fmt("zig cc {s}", .{options.basename}));
    run.expectExitCode(0);
    run.setCwd(b.path(""));
    addZigCommonArgs(run, zig_global_cache_dir);
    run.addArgs(&.{
        "-Os",
        "-std=gnu99",
        "-ffunction-sections",
        "-fdata-sections",
        "-DARCH_RISCV",
        "-c",
    });
    if (options.bypass_conf_header) {
        run.addArg("-D__CH32V30x_CONF_H");
    }
    addIncludeDirs(run, b);
    const output = run.addPrefixedOutputFileArg("-o", options.basename);
    run.addFileArg(b.path(options.source_path));
    return output;
}

fn addAssemblyObject(
    b: *std.Build,
    zig_global_cache_dir: []const u8,
    basename: []const u8,
    source_path: []const u8,
) std.Build.LazyPath {
    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "cc" });
    run.setName(b.fmt("zig cc {s}", .{basename}));
    run.expectExitCode(0);
    run.setCwd(b.path(""));
    addZigCommonArgs(run, zig_global_cache_dir);
    run.addArgs(&.{
        "-Os",
        "-c",
    });
    const output = run.addPrefixedOutputFileArg("-o", basename);
    run.addFileArg(b.path(source_path));
    return output;
}

fn addZigObject(
    b: *std.Build,
    zig_global_cache_dir: []const u8,
    basename: []const u8,
    source_path: []const u8,
) std.Build.LazyPath {
    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build-obj" });
    run.setName(b.fmt("zig build-obj {s}", .{basename}));
    run.expectExitCode(0);
    run.setCwd(b.path(""));
    addZigCommonArgs(run, zig_global_cache_dir);
    run.addArgs(&.{
        "-O",
        zig_optimize,
        "-ffunction-sections",
        "-fdata-sections",
    });
    addIncludeDirs(run, b);
    const output = run.addPrefixedOutputFileArg("-femit-bin=", basename);
    run.addFileArg(b.path(source_path));
    return output;
}
