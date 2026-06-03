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

pub fn addLvgl(
    b: *std.Build,
    exe: *std.Build.Step.Compile,
    flags: []const []const u8,
    // target: std.Build.ResolvedTarget,
    // optimize: std.builtin.OptimizeMode,
) void {
    // const lvgl_mod = b.createModule(.{
    //     .target = target,
    //     .optimize = optimize,
    // });

    // lvgl_mod.addIncludePath(b.path("deps/lvgl"));
    // // lvgl_mod.addCMacro("LV_CONF_INCLUDE_SIMPLE", "1");

    // var c_files: std.ArrayList([]const u8) = .empty;

    // const src_abs = b.path("deps/lvgl/src").getPath(b);

    // var threaded: std.Io.Threaded = .init(b.allocator, .{});
    // const io = threaded.io();
    // defer threaded.deinit();

    // collectCFiles(b.allocator, io, src_abs, &c_files) catch @panic("collect lvgl c files failed");

    // lvgl_mod.addCSourceFiles(.{
    //     .root = b.path("deps/lvgl/src"),
    //     .files = c_files.items,
    //     .flags = &.{
    //         "-std=c99",
    //         "-Os",
    //     },
    // });

    // const lvgl_lib = b.addLibrary(.{
    //     .name = "lvgl",
    //     .root_module = lvgl_mod,
    // });

    // exe.root_module.linkLibrary(lvgl_lib);

    // exe.root_module.addIncludePath(b.path("deps/lvgl"));
    // exe.root_module.addCMacro("LV_CONF_INCLUDE_SIMPLE", "1");

    var threaded: std.Io.Threaded = .init(b.allocator, .{});
    const io = threaded.io();
    defer threaded.deinit();
    var c_files: std.ArrayList([]const u8) = .empty;
    const src_abs = b.path("deps/lvgl/src").getPath(b);
    collectCFiles(b.allocator, io, src_abs, &c_files) catch @panic("collect lvgl c files failed");

    exe.root_module.addIncludePath(b.path("deps/lvgl"));
    exe.root_module.addIncludePath(b.path("deps/lvgl/src"));
    exe.root_module.addIncludePath(b.path("deps/lvgl/examples"));
    exe.root_module.addCSourceFiles(.{
        .root = b.path("deps/lvgl/src"),
        .files = c_files.items,
        .flags = flags,
    });

    exe.root_module.addCSourceFile(.{
        .file = b.path("deps/lvgl/examples/widgets/calendar/lv_example_calendar_basic.c"),
        .flags = flags,
    });
}
