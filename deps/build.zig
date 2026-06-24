const std = @import("std");

fn collectCFiles(
    allocator: std.mem.Allocator,
    io: std.Io,
    search_dir: []const u8,
    out: *std.ArrayList([]const u8),
) !void {
    var dir = try std.Io.Dir.cwd().openDir(io, search_dir, .{ .iterate = true });
    defer dir.close(io);

    // 创建一个 Walker 对象
    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        // entry.path 已经是相对于 search_dir 的相对路径了
        if (entry.kind == .file and std.mem.endsWith(u8, entry.basename, ".c")) {
            // 将路径复制一份存入 out
            const path_copy = try allocator.dupe(u8, entry.path);
            try out.append(allocator, path_copy);
        }
    }
}

pub fn addTusb(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    flags: []const []const u8,
) *std.Build.Step.Compile {
    const tusb_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
    });

    tusb_mod.addIncludePath(b.path("deps/tusb/src"));
    tusb_mod.addIncludePath(b.path("deps/tusb/hw"));
    tusb_mod.addIncludePath(b.path("zig-src/c/inc"));
    tusb_mod.addIncludePath(b.path("hal/Core"));
    tusb_mod.addIncludePath(b.path("hal/Peripheral/inc"));

    tusb_mod.addCSourceFiles(.{
        .root = b.path("deps/tusb/src"),
        .files = &.{
            // common
            "tusb.c",
            "common/tusb_fifo.c",
            // device
            "device/usbd.c",
            "class/audio/audio_device.c",
            "class/cdc/cdc_device.c",
            "class/dfu/dfu_device.c",
            "class/dfu/dfu_rt_device.c",
            "class/hid/hid_device.c",
            "class/midi/midi_device.c",
            "class/midi/midi2_device.c",
            "class/msc/msc_device.c",
            "class/mtp/mtp_device.c",
            "class/net/ecm_rndis_device.c",
            "class/net/ncm_device.c",
            "class/printer/printer_device.c",
            "class/usbtmc/usbtmc_device.c",
            "class/video/video_device.c",
            "class/vendor/vendor_device.c",
            // host
            "host/usbh.c",
            "host/hub.c",
            "class/cdc/cdc_host.c",
            "class/hid/hid_host.c",
            "class/midi/midi_host.c",
            "class/midi/midi2_host.c",
            "class/msc/msc_host.c",
            "class/vendor/vendor_host.c",
            // typec
            "typec/usbc.c",
            // wch
            "portable/wch/dcd_ch32_usbfs.c",
            "portable/wch/dcd_ch32_usbhs.c",
            "portable/wch/hcd_ch32_usbfs.c",
        },
        .flags = flags,
    });
    tusb_mod.addCMacro("CFG_TUSB_MCU", "OPT_MCU_CH32V307");
    tusb_mod.addCMacro("CFG_TUD_WCH_USBIP_USBHS", "1");
    tusb_mod.addCMacro("ARCH_RISCV", "1");

    const lib = b.addLibrary(.{
        .name = "tusb",
        .root_module = tusb_mod,
    });

    return lib;
}

pub fn addLvgl(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    flags: []const []const u8,
) *std.Build.Step.Compile {
    var threaded: std.Io.Threaded = .init(b.allocator, .{});
    const io = threaded.io();
    defer threaded.deinit();
    var c_files: std.ArrayList([]const u8) = .empty;
    const src_abs = b.path("deps/lvgl/src").getPath(b);
    collectCFiles(b.allocator, io, src_abs, &c_files) catch @panic("collect lvgl c files failed");

    const lvgl_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
    });

    lvgl_mod.addIncludePath(b.path("deps/lvgl"));
    lvgl_mod.addIncludePath(b.path("deps/lvgl/src"));
    lvgl_mod.addIncludePath(b.path("deps/lvgl/examples"));
    lvgl_mod.addIncludePath(b.path("zig-src/c/inc"));

    lvgl_mod.addCSourceFiles(.{
        .root = b.path("deps/lvgl/src"),
        .files = c_files.items,
        .flags = flags,
    });

    lvgl_mod.addCSourceFile(.{
        .file = b.path("deps/lvgl/examples/widgets/calendar/lv_example_calendar_basic.c"),
        .flags = flags,
    });

    const lib = b.addLibrary(.{
        .name = "lvgl",
        .root_module = lvgl_mod,
    });

    return lib;
}
