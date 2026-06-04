//! string.zig (适配现代 Zig 语法)

export fn memcpy(noalias dest: ?*anyopaque, noalias src: ?*const anyopaque, n: usize) callconv(.C) ?*anyopaque {
    if (dest == null or src == null or n == 0) return dest;

    const d: [*]u8 = @ptrCast(dest.?);
    const s: [*]const u8 = @ptrCast(src.?);

    var i: usize = 0;
    while (i < n) : (i += 1) {
        d[i] = s[i];
    }
    return dest;
}

export fn memset(s: ?*anyopaque, c: c_int, n: usize) callconv(.C) ?*anyopaque {
    if (s == null or n == 0) return s;

    const d: [*]u8 = @ptrCast(s.?);
    // 现代 Zig 自动推导 @intCast 目标类型
    const value: u8 = @intCast(c & 0xFF);

    var i: usize = 0;
    while (i < n) : (i += 1) {
        d[i] = value;
    }
    return s;
}

export fn memmove(dest: ?*anyopaque, src: ?*const anyopaque, n: usize) callconv(.C) ?*anyopaque {
    if (dest == null or src == null or n == 0) return dest;

    const d: [*]u8 = @ptrCast(dest.?);
    const s: [*]const u8 = @ptrCast(src.?);

    if (@intFromPtr(d) > @intFromPtr(s) and @intFromPtr(d) < @intFromPtr(s) + n) {
        var i: usize = n;
        while (i > 0) {
            i -= 1;
            d[i] = s[i];
        }
    } else {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            d[i] = s[i];
        }
    }
    return dest;
}

export fn memcmp(s1: ?*const anyopaque, s2: ?*const anyopaque, n: usize) callconv(.C) c_int {
    if (s1 == null or s2 == null or n == 0) return 0;

    const p1: [*]const u8 = @ptrCast(s1.?);
    const p2: [*]const u8 = @ptrCast(s2.?);

    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (p1[i] != p2[i]) {
            return if (p1[i] < p2[i]) -1 else 1;
        }
    }
    return 0;
}

export fn strlen(s: ?[*c]const u8) callconv(.C) usize {
    if (s == null) return 0;

    var len: usize = 0;
    while (s.?[len] != 0) : (len += 1) {}
    return len;
}

export fn strcmp(s1: ?[*c]const u8, s2: ?[*c]const u8) callconv(.C) c_int {
    if (s1 == null or s2 == null) return 0;

    var i: usize = 0;
    while (s1.?[i] != 0 and s1.?[i] == s2.?[i]) : (i += 1) {}

    const c1: c_int = s1.?[i];
    const c2: c_int = s2.?[i];
    return c1 - c2;
}

export fn strncmp(s1: ?[*c]const u8, s2: ?[*c]const u8, n: usize) callconv(.C) c_int {
    if (s1 == null or s2 == null or n == 0) return 0;

    var i: usize = 0;
    while (i < n) : (i += 1) {
        if (s1.?[i] == 0 or s1.?[i] != s2.?[i]) {
            const c1: c_int = s1.?[i];
            const c2: c_int = s2.?[i];
            return c1 - c2;
        }
    }
    return 0;
}
