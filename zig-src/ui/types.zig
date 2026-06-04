pub const Align = enum {
    left,
    center,
    right,
};

pub const Rect = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,

    pub fn init(x: i32, y: i32, w: i32, h: i32) Rect {
        return .{ .x = x, .y = y, .w = w, .h = h };
    }

    pub fn isEmpty(self: Rect) bool {
        return self.w <= 0 or self.h <= 0;
    }

    pub fn area(self: Rect) i32 {
        if (self.isEmpty()) return 0;
        return self.w * self.h;
    }

    pub fn unionRect(a: Rect, b: Rect) Rect {
        if (a.isEmpty()) return b;
        if (b.isEmpty()) return a;

        const x1 = @min(a.x, b.x);
        const y1 = @min(a.y, b.y);
        const x2 = @max(a.x + a.w, b.x + b.w);
        const y2 = @max(a.y + a.h, b.y + b.h);
        return .{
            .x = x1,
            .y = y1,
            .w = x2 - x1,
            .h = y2 - y1,
        };
    }

    pub fn intersect(a: Rect, b: Rect) ?Rect {
        if (a.isEmpty() or b.isEmpty()) return null;

        const x1 = @max(a.x, b.x);
        const y1 = @max(a.y, b.y);
        const x2 = @min(a.x + a.w, b.x + b.w);
        const y2 = @min(a.y + a.h, b.y + b.h);

        if (x1 < x2 and y1 < y2) {
            return .{
                .x = x1,
                .y = y1,
                .w = x2 - x1,
                .h = y2 - y1,
            };
        }
        return null;
    }

    pub fn contains(self: Rect, x: i32, y: i32) bool {
        return x >= self.x and x < self.x + self.w and y >= self.y and y < self.y + self.h;
    }

    pub fn containsRect(self: Rect, other: Rect) bool {
        if (other.isEmpty()) return true;
        return other.x >= self.x and
            other.y >= self.y and
            other.x + other.w <= self.x + self.w and
            other.y + other.h <= self.y + self.h;
    }

    pub fn expanded(self: Rect, amount: i32) Rect {
        return .{
            .x = self.x - amount,
            .y = self.y - amount,
            .w = self.w + amount * 2,
            .h = self.h + amount * 2,
        };
    }
};

pub const FontMetrics = struct {
    w: i32,
    h: i32,
};

pub fn fontMetrics(size: u32) ?FontMetrics {
    return switch (size) {
        12 => .{ .w = 6, .h = 12 },
        16 => .{ .w = 8, .h = 16 },
        24 => .{ .w = 12, .h = 24 },
        else => null,
    };
}

pub fn textSize(size: u32, text: []const u8) FontMetrics {
    const metrics = fontMetrics(size) orelse return .{ .w = 0, .h = 0 };
    var line_w: i32 = 0;
    var max_w: i32 = 0;
    var lines: i32 = 1;

    for (text) |ch| {
        if (ch == '\n') {
            max_w = @max(max_w, line_w);
            line_w = 0;
            lines += 1;
        } else {
            line_w += metrics.w;
        }
    }

    max_w = @max(max_w, line_w);
    return .{ .w = max_w, .h = lines * metrics.h };
}

pub fn alignedX(area: Rect, content_w: i32, text_align: Align) i32 {
    return switch (text_align) {
        .left => area.x,
        .center => area.x + @max(0, @divTrunc(area.w - content_w, 2)),
        .right => area.x + @max(0, area.w - content_w),
    };
}

pub fn absI32(value: i32) i32 {
    return if (value < 0) -value else value;
}
