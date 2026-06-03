const std = @import("std");

// string.h
export fn memcpy(dest: *anyopaque, src: *const anyopaque, n: usize) *anyopaque {
    const d: [*]u8 = @ptrCast(dest);
    const s: [*]const u8 = @ptrCast(src);
    for (0..n) |i| d[i] = s[i];
    return dest;
}

export fn memset(s: *anyopaque, c: i32, n: usize) *anyopaque {
    const d: [*]u8 = @ptrCast(s);
    for (0..n) |i| d[i] = @intCast(c & 0xFF);
    return s;
}

export fn memmove(dest: *anyopaque, src: *const anyopaque, n: usize) *anyopaque {
    const d: [*]u8 = @ptrCast(dest);
    const s: [*]const u8 = @ptrCast(src);
    if (@intFromPtr(dest) < @intFromPtr(src)) {
        for (0..n) |i| d[i] = s[i];
    } else {
        var i = n;
        while (i > 0) : (i -= 1) d[i - 1] = s[i - 1];
    }
    return dest;
}

export fn memcmp(s1: *const anyopaque, s2: *const anyopaque, n: usize) i32 {
    const a: [*]const u8 = @ptrCast(s1);
    const b: [*]const u8 = @ptrCast(s2);
    for (0..n) |i| {
        if (a[i] != b[i]) return @as(i32, a[i]) - @as(i32, b[i]);
    }
    return 0;
}

export fn strlen(s: [*:0]const u8) usize {
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {}
    return i;
}

export fn strcmp(s1: [*:0]const u8, s2: [*:0]const u8) i32 {
    var i: usize = 0;
    while (s1[i] == s2[i] and s1[i] != 0) : (i += 1) {}
    return @as(i32, s1[i]) - @as(i32, s2[i]);
}

export fn strncmp(s1: [*:0]const u8, s2: [*:0]const u8, n: usize) i32 {
    var i: usize = 0;
    while (i < n and s1[i] == s2[i] and s1[i] != 0) : (i += 1) {}
    if (i == n) return 0;
    return @as(i32, s1[i]) - @as(i32, s2[i]);
}

export fn strcpy(dest: [*]u8, src: [*:0]const u8) [*]u8 {
    var i: usize = 0;
    while (src[i] != 0) : (i += 1) dest[i] = src[i];
    dest[i] = 0;
    return dest;
}

export fn strncpy(dest: [*]u8, src: [*:0]const u8, n: usize) [*]u8 {
    var i: usize = 0;
    while (i < n and src[i] != 0) : (i += 1) dest[i] = src[i];
    while (i < n) : (i += 1) dest[i] = 0;
    return dest;
}

export fn strcat(dest: [*:0]u8, src: [*:0]const u8) [*]u8 {
    var i: usize = 0;
    while (dest[i] != 0) : (i += 1) {}
    var j: usize = 0;
    while (src[j] != 0) : (j += 1) dest[i + j] = src[j];
    dest[i + j] = 0;
    return dest;
}

export fn strchr(s: [*:0]const u8, c: i32) ?[*]u8 {
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {
        if (s[i] == @as(u8, @intCast(c & 0xFF))) return @ptrCast(@constCast(s + i));
    }
    return null;
}

export fn strstr(haystack: [*:0]const u8, needle: [*:0]const u8) ?[*]u8 {
    var i: usize = 0;
    const nlen = strlen(needle);
    if (nlen == 0) return @ptrCast(@constCast(haystack));
    while (haystack[i] != 0) : (i += 1) {
        if (memcmp(haystack + i, needle, nlen) == 0)
            return @ptrCast(@constCast(haystack + i));
    }
    return null;
}

// stdlib.h
export fn abs(x: i32) i32 {
    return if (x < 0) -x else x;
}

export fn labs(x: i64) i64 {
    return if (x < 0) -x else x;
}
