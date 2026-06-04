const std = @import("std");
const lcd = @import("lcd.zig");
const font = @import("font.zig");
const Color = @import("color.zig").Color565;

const dirty_max_areas = 16;
const dirty_merge_slack = 1;
const dirty_merge_waste_min = 64;
const default_bg = Color.BLACK;

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

pub const Canvas = struct {
    area: Rect,
    buf: []u16,
    clip: Rect,

    pub fn init(area: Rect, buf: []u16) Canvas {
        return .{
            .area = area,
            .buf = buf,
            .clip = area,
        };
    }

    pub fn setClip(self: *Canvas, clip: Rect) void {
        self.clip = Rect.intersect(self.area, clip) orelse Rect.init(0, 0, 0, 0);
    }

    fn indexOf(self: *const Canvas, x: i32, y: i32) usize {
        const lx: usize = @intCast(x - self.area.x);
        const ly: usize = @intCast(y - self.area.y);
        return ly * @as(usize, @intCast(self.area.w)) + lx;
    }

    fn putRaw(self: *Canvas, x: i32, y: i32, raw_color: u16) void {
        if (!self.clip.contains(x, y)) return;
        self.buf[self.indexOf(x, y)] = raw_color;
    }

    pub fn drawPoint(self: *Canvas, x: i32, y: i32, color: Color) void {
        self.putRaw(x, y, color.toRgb565());
    }

    pub fn fillRect(self: *Canvas, x: i32, y: i32, w: i32, h: i32, color: Color) void {
        if (w <= 0 or h <= 0) return;

        const draw_rect = Rect.init(x, y, w, h);
        const res = Rect.intersect(draw_rect, self.clip) orelse return;
        const raw_color = color.toRgb565();
        const row_len: usize = @intCast(res.w);

        var iy = res.y;
        while (iy < res.y + res.h) : (iy += 1) {
            const start = self.indexOf(res.x, iy);
            @memset(self.buf[start .. start + row_len], raw_color);
        }
    }

    pub fn drawHLine(self: *Canvas, x: i32, y: i32, w: i32, color: Color) void {
        self.fillRect(x, y, w, 1, color);
    }

    pub fn drawVLine(self: *Canvas, x: i32, y: i32, h: i32, color: Color) void {
        self.fillRect(x, y, 1, h, color);
    }

    pub fn drawRect(self: *Canvas, x: i32, y: i32, w: i32, h: i32, color: Color) void {
        if (w <= 0 or h <= 0) return;
        const rect = Rect.init(x, y, w, h);
        if (Rect.intersect(rect, self.clip) == null) return;

        self.drawHLine(x, y, w, color);
        if (h > 1) self.drawHLine(x, y + h - 1, w, color);
        if (h > 2) {
            self.drawVLine(x, y + 1, h - 2, color);
            if (w > 1) self.drawVLine(x + w - 1, y + 1, h - 2, color);
        }
    }

    pub fn drawLine(self: *Canvas, x1: i32, y1: i32, x2: i32, y2: i32, color: Color) void {
        if (x1 == x2) {
            self.drawVLine(x1, @min(y1, y2), absI32(y2 - y1) + 1, color);
            return;
        }
        if (y1 == y2) {
            self.drawHLine(@min(x1, x2), y1, absI32(x2 - x1) + 1, color);
            return;
        }

        const line_rect = Rect.init(
            @min(x1, x2),
            @min(y1, y2),
            absI32(x2 - x1) + 1,
            absI32(y2 - y1) + 1,
        );
        if (Rect.intersect(line_rect, self.clip) == null) return;

        var dx = x2 - x1;
        var dy = y2 - y1;
        var row = x1;
        var col = y1;

        const incx: i32 = if (dx > 0) 1 else if (dx == 0) 0 else blk: {
            dx = -dx;
            break :blk -1;
        };
        const incy: i32 = if (dy > 0) 1 else if (dy == 0) 0 else blk: {
            dy = -dy;
            break :blk -1;
        };
        const distance = @max(dx, dy);
        const raw_color = color.toRgb565();

        var xerr: i32 = 0;
        var yerr: i32 = 0;
        var i: i32 = 0;
        while (i <= distance) : (i += 1) {
            self.putRaw(row, col, raw_color);
            xerr += dx;
            yerr += dy;
            if (xerr > distance) {
                xerr -= distance;
                row += incx;
            }
            if (yerr > distance) {
                yerr -= distance;
                col += incy;
            }
        }
    }

    pub fn drawCircle(self: *Canvas, x0: i32, y0: i32, r: i32, color: Color) void {
        if (r <= 0) return;

        const circle_rect = Rect.init(x0 - r, y0 - r, r * 2 + 1, r * 2 + 1);
        if (Rect.intersect(circle_rect, self.clip) == null) return;

        const raw_color = color.toRgb565();
        var a: i32 = 0;
        var b: i32 = r;
        var di: i32 = 3 - r * 2;

        while (a <= b) {
            self.putRaw(x0 + a, y0 - b, raw_color);
            self.putRaw(x0 + b, y0 - a, raw_color);
            self.putRaw(x0 + b, y0 + a, raw_color);
            self.putRaw(x0 + a, y0 + b, raw_color);
            self.putRaw(x0 - a, y0 + b, raw_color);
            self.putRaw(x0 - b, y0 + a, raw_color);
            self.putRaw(x0 - b, y0 - a, raw_color);
            self.putRaw(x0 - a, y0 - b, raw_color);

            a += 1;
            if (di < 0) {
                di += 4 * a + 6;
            } else {
                di += 10 + 4 * (a - b);
                b -= 1;
            }
        }
    }

    fn glyphLit(ch: u8, size: u32, col: i32, row: i32) bool {
        const idx: usize = @as(usize, ch - 0x20);
        const ucol: usize = @intCast(col);

        return switch (size) {
            12 => blk: {
                const val = (@as(u16, font.asc2_1206[idx][ucol * 2]) << 8) |
                    @as(u16, font.asc2_1206[idx][ucol * 2 + 1]);
                const bit_pos: u4 = @intCast(15 - row);
                break :blk ((val >> bit_pos) & 1) != 0;
            },
            16 => blk: {
                const val = (@as(u16, font.asc2_1608[idx][ucol * 2]) << 8) |
                    @as(u16, font.asc2_1608[idx][ucol * 2 + 1]);
                const bit_pos: u4 = @intCast(15 - row);
                break :blk ((val >> bit_pos) & 1) != 0;
            },
            24 => blk: {
                const val = (@as(u32, font.asc2_2412[idx][ucol * 3]) << 16) |
                    (@as(u32, font.asc2_2412[idx][ucol * 3 + 1]) << 8) |
                    @as(u32, font.asc2_2412[idx][ucol * 3 + 2]);
                const bit_pos: u5 = @intCast(23 - row);
                break :blk ((val >> bit_pos) & 1) != 0;
            },
            else => false,
        };
    }

    pub fn showChar(self: *Canvas, x_off: i32, y_off: i32, ch: u8, size: u32, color: Color, bg_color: ?Color) void {
        if (ch < 0x20 or ch > 0x7e) return;
        const metrics = fontMetrics(size) orelse return;

        const char_rect = Rect.init(x_off, y_off, metrics.w, metrics.h);
        const res = Rect.intersect(char_rect, self.clip) orelse return;
        const raw_color = color.toRgb565();
        const raw_bg = if (bg_color) |bg| bg.toRgb565() else null;

        var y = res.y;
        while (y < res.y + res.h) : (y += 1) {
            const row = y - y_off;
            var x = res.x;
            while (x < res.x + res.w) : (x += 1) {
                const col = x - x_off;
                if (glyphLit(ch, size, col, row)) {
                    self.buf[self.indexOf(x, y)] = raw_color;
                } else if (raw_bg) |bg| {
                    self.buf[self.indexOf(x, y)] = bg;
                }
            }
        }
    }

    pub fn showString(self: *Canvas, x_off: i32, y_off: i32, size: u32, str: []const u8, color: Color, bg_color: ?Color) void {
        const metrics = fontMetrics(size) orelse return;
        var cx = x_off;
        var cy = y_off;

        for (str) |ch| {
            if (ch == '\n') {
                cx = x_off;
                cy += metrics.h;
                continue;
            }
            self.showChar(cx, cy, ch, size, color, bg_color);
            cx += metrics.w;
        }
    }

    pub fn drawImageRgb565(self: *Canvas, x: i32, y: i32, w: i32, h: i32, pixels: []const u16, stride: i32, color_key: ?u16) void {
        if (w <= 0 or h <= 0 or stride < w) return;
        const img_rect = Rect.init(x, y, w, h);
        const res = Rect.intersect(img_rect, self.clip) orelse return;
        const row_len: usize = @intCast(res.w);

        var iy = res.y;
        while (iy < res.y + res.h) : (iy += 1) {
            const src_x: usize = @intCast(res.x - x);
            const src_y: usize = @intCast(iy - y);
            const src_start = src_y * @as(usize, @intCast(stride)) + src_x;
            const dst_start = self.indexOf(res.x, iy);

            if (color_key == null) {
                @memcpy(self.buf[dst_start .. dst_start + row_len], pixels[src_start .. src_start + row_len]);
            } else {
                const key = color_key.?;
                var ix: usize = 0;
                while (ix < row_len) : (ix += 1) {
                    const px = pixels[src_start + ix];
                    if (px != key) self.buf[dst_start + ix] = px;
                }
            }
        }
    }

    pub fn flush(self: *Canvas) void {
        lcd.flushPixels(
            @intCast(self.area.x),
            @intCast(self.area.y),
            @intCast(self.area.x + self.area.w - 1),
            @intCast(self.area.y + self.area.h - 1),
            self.buf.ptr,
        );
    }
};

pub const Node = struct {
    area: Rect,
    parent: ?*Node = null,
    first_child: ?*Node = null,
    last_child: ?*Node = null,
    next: ?*Node = null,
    prev: ?*Node = null,
    display: ?*Display = null,
    hidden: bool = false,
    draw_cb: ?*const fn (node: *Node, canvas: *Canvas) void = null,

    pub fn init(x: i32, y: i32, w: i32, h: i32) Node {
        return .{
            .area = Rect.init(x, y, w, h),
        };
    }

    pub fn getAbsArea(self: *const Node) Rect {
        var abs_area = self.area;
        var p = self.parent;
        while (p) |par| {
            abs_area.x += par.area.x;
            abs_area.y += par.area.y;
            p = par.parent;
        }
        return abs_area;
    }

    fn setDisplayRecursive(self: *Node, display: ?*Display) void {
        self.display = display;
        var child = self.first_child;
        while (child) |c| {
            c.setDisplayRecursive(display);
            child = c.next;
        }
    }

    pub fn addChild(self: *Node, child: *Node) void {
        if (child.parent) |old_parent| {
            old_parent.removeChild(child);
        }

        child.parent = self;
        child.next = null;
        child.prev = self.last_child;
        child.setDisplayRecursive(self.display);

        if (self.last_child) |last| {
            last.next = child;
        } else {
            self.first_child = child;
        }
        self.last_child = child;

        child.invalidate();
    }

    pub fn removeChild(self: *Node, child: *Node) void {
        if (child.parent != self) return;

        const old_abs = child.getAbsArea();
        if (child.prev) |p| p.next = child.next else self.first_child = child.next;
        if (child.next) |n| n.prev = child.prev else self.last_child = child.prev;
        child.parent = null;
        child.next = null;
        child.prev = null;
        child.setDisplayRecursive(null);

        if (self.display) |disp| {
            disp.markDirty(old_abs);
        } else if (Display.current) |disp| {
            disp.markDirty(old_abs);
        }
    }

    pub fn setPos(self: *Node, x: i32, y: i32) void {
        if (self.area.x == x and self.area.y == y) return;
        const old_abs = self.getAbsArea();
        self.area.x = x;
        self.area.y = y;
        self.invalidateArea(old_abs);
        self.invalidate();
    }

    pub fn setSize(self: *Node, w: i32, h: i32) void {
        if (self.area.w == w and self.area.h == h) return;
        const old_abs = self.getAbsArea();
        self.area.w = w;
        self.area.h = h;
        self.invalidateArea(old_abs);
        self.invalidate();
    }

    pub fn setHidden(self: *Node, hidden: bool) void {
        if (self.hidden == hidden) return;
        self.invalidate();
        self.hidden = hidden;
        self.invalidate();
    }

    pub fn invalidate(self: *Node) void {
        self.invalidateArea(self.getAbsArea());
    }

    pub fn invalidateArea(self: *Node, abs_area: Rect) void {
        if (self.display) |disp| {
            disp.markDirty(abs_area);
        } else if (Display.current) |disp| {
            disp.markDirty(abs_area);
        }
    }
};

pub const Label = struct {
    node: Node,
    text: []const u8,
    color: Color = Color.WHITE,
    bg_color: ?Color = null,
    font_size: u32 = 16,
    text_align: Align = .left,

    pub fn init(x: i32, y: i32, w: i32, h: i32, text: []const u8) Label {
        var self = Label{
            .node = Node.init(x, y, w, h),
            .text = text,
        };
        self.node.draw_cb = draw;
        return self;
    }

    pub fn asNode(self: *Label) *Node {
        return &self.node;
    }

    pub fn setText(self: *Label, text: []const u8) void {
        if (std.mem.eql(u8, self.text, text)) return;
        self.node.invalidate();
        self.text = text;
        self.node.invalidate();
    }

    pub fn setColor(self: *Label, color: Color) void {
        if (self.color.data == color.data) return;
        self.color = color;
        self.node.invalidate();
    }

    pub fn setBgColor(self: *Label, bg_color: ?Color) void {
        const old = if (self.bg_color) |c| c.data else null;
        const new = if (bg_color) |c| c.data else null;
        if (old == new) return;
        self.bg_color = bg_color;
        self.node.invalidate();
    }

    fn draw(node: *Node, canvas: *Canvas) void {
        const self: *Label = @fieldParentPtr("node", node);
        const abs = node.getAbsArea();
        if (self.bg_color) |bg| {
            canvas.fillRect(abs.x, abs.y, abs.w, abs.h, bg);
        }

        const size = textSize(self.font_size, self.text);
        const x = alignedX(abs, size.w, self.text_align);
        const y = abs.y + @max(0, @divTrunc(abs.h - size.h, 2));
        canvas.showString(x, y, self.font_size, self.text, self.color, self.bg_color);
    }
};

pub const Button = struct {
    node: Node,
    text: []const u8,
    font_size: u32 = 16,
    text_color: Color = Color.WHITE,
    bg_color: Color = Color.BLUE,
    pressed_bg_color: Color = Color.DARKGRAY,
    disabled_bg_color: Color = Color.LGRAY,
    border_color: Color = Color.WHITE,
    pressed: bool = false,
    enabled: bool = true,

    pub fn init(x: i32, y: i32, w: i32, h: i32, text: []const u8) Button {
        var self = Button{
            .node = Node.init(x, y, w, h),
            .text = text,
        };
        self.node.draw_cb = draw;
        return self;
    }

    pub fn asNode(self: *Button) *Node {
        return &self.node;
    }

    pub fn setText(self: *Button, text: []const u8) void {
        if (std.mem.eql(u8, self.text, text)) return;
        self.text = text;
        self.node.invalidate();
    }

    pub fn setPressed(self: *Button, pressed: bool) void {
        if (self.pressed == pressed) return;
        self.pressed = pressed;
        self.node.invalidate();
    }

    pub fn setEnabled(self: *Button, enabled: bool) void {
        if (self.enabled == enabled) return;
        self.enabled = enabled;
        self.node.invalidate();
    }

    fn draw(node: *Node, canvas: *Canvas) void {
        const self: *Button = @fieldParentPtr("node", node);
        const abs = node.getAbsArea();
        const bg = if (!self.enabled) self.disabled_bg_color else if (self.pressed) self.pressed_bg_color else self.bg_color;

        canvas.fillRect(abs.x, abs.y, abs.w, abs.h, bg);
        canvas.drawRect(abs.x, abs.y, abs.w, abs.h, self.border_color);

        const size = textSize(self.font_size, self.text);
        const x = alignedX(abs, size.w, .center);
        const y = abs.y + @max(0, @divTrunc(abs.h - size.h, 2));
        canvas.showString(x, y, self.font_size, self.text, self.text_color, bg);
    }
};

pub const Image = struct {
    node: Node,
    pixels: []const u16 = &.{},
    stride: i32 = 0,
    color_key: ?u16 = null,
    bg_color: ?Color = null,

    pub fn init(x: i32, y: i32, w: i32, h: i32, pixels: []const u16) Image {
        var self = Image{
            .node = Node.init(x, y, w, h),
            .pixels = pixels,
            .stride = w,
        };
        self.node.draw_cb = draw;
        return self;
    }

    pub fn asNode(self: *Image) *Node {
        return &self.node;
    }

    pub fn setSource(self: *Image, pixels: []const u16, w: i32, h: i32, stride: i32) void {
        self.node.invalidate();
        self.pixels = pixels;
        self.stride = stride;
        self.node.area.w = w;
        self.node.area.h = h;
        self.node.invalidate();
    }

    pub fn setColorKey(self: *Image, color_key: ?u16) void {
        if (self.color_key == color_key) return;
        self.color_key = color_key;
        self.node.invalidate();
    }

    fn draw(node: *Node, canvas: *Canvas) void {
        const self: *Image = @fieldParentPtr("node", node);
        const abs = node.getAbsArea();
        if (self.bg_color) |bg| {
            canvas.fillRect(abs.x, abs.y, abs.w, abs.h, bg);
        }
        canvas.drawImageRgb565(abs.x, abs.y, abs.w, abs.h, self.pixels, self.stride, self.color_key);
    }
};

pub const Display = struct {
    screen: Node,
    dirty_areas: [dirty_max_areas]Rect = undefined,
    dirty_count: usize = 0,
    draw_buf: []u16,
    allocator: std.mem.Allocator,

    pub var current: ?*Display = null;

    pub fn init(allocator: std.mem.Allocator, buffer_height: u32) !Display {
        const buf_len = @as(usize, lcd.WIDTH) * buffer_height;
        const buf = try allocator.alloc(u16, buf_len);

        return .{
            .screen = Node.init(0, 0, lcd.WIDTH, lcd.HEIGHT),
            .draw_buf = buf,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Display) void {
        self.allocator.free(self.draw_buf);
        if (current == self) current = null;
    }

    pub fn bind(self: *Display) void {
        current = self;
        self.screen.setDisplayRecursive(self);
        self.markDirty(self.screen.area);
    }

    pub fn createNode(self: *Display, x: i32, y: i32, w: i32, h: i32, draw_cb: ?*const fn (node: *Node, canvas: *Canvas) void) !*Node {
        const node = try self.allocator.create(Node);
        node.* = Node.init(x, y, w, h);
        node.display = self;
        node.draw_cb = draw_cb;
        return node;
    }

    pub fn createLabel(self: *Display, x: i32, y: i32, w: i32, h: i32, text: []const u8) !*Label {
        const label = try self.allocator.create(Label);
        label.* = Label.init(x, y, w, h, text);
        label.node.display = self;
        return label;
    }

    pub fn createButton(self: *Display, x: i32, y: i32, w: i32, h: i32, text: []const u8) !*Button {
        const button = try self.allocator.create(Button);
        button.* = Button.init(x, y, w, h, text);
        button.node.display = self;
        return button;
    }

    pub fn createImage(self: *Display, x: i32, y: i32, w: i32, h: i32, pixels: []const u16) !*Image {
        const image = try self.allocator.create(Image);
        image.* = Image.init(x, y, w, h, pixels);
        image.node.display = self;
        return image;
    }

    pub fn screenAddChild(self: *Display, child: *Node) void {
        self.screen.addChild(child);
    }

    pub fn markDirty(self: *Display, rect: Rect) void {
        const bounded = Rect.intersect(rect, self.screen.area) orelse return;
        if (bounded.isEmpty()) return;

        if (bounded.containsRect(self.screen.area)) {
            self.dirty_areas[0] = self.screen.area;
            self.dirty_count = 1;
            return;
        }

        var i: usize = 0;
        while (i < self.dirty_count) : (i += 1) {
            if (self.dirty_areas[i].containsRect(bounded)) return;
            if (bounded.containsRect(self.dirty_areas[i])) {
                self.dirty_areas[i] = bounded;
                self.mergeDirtyAreas();
                return;
            }
        }

        if (self.dirty_count == self.dirty_areas.len) {
            self.mergeDirtyAreas();
            if (self.dirty_count == self.dirty_areas.len) self.mergeBestDirtyPair();
        }

        self.dirty_areas[self.dirty_count] = bounded;
        self.dirty_count += 1;
        self.mergeDirtyAreas();
    }

    fn shouldMergeDirty(a: Rect, b: Rect) bool {
        if (Rect.intersect(a.expanded(dirty_merge_slack), b) != null) return true;

        const merged = Rect.unionRect(a, b);
        const sum_area = a.area() + b.area();
        const waste = merged.area() - sum_area;
        const allowed_waste = @max(dirty_merge_waste_min, @divTrunc(sum_area, 4));
        return waste <= allowed_waste;
    }

    fn removeDirtyAt(self: *Display, index: usize) void {
        if (index < self.dirty_count - 1) {
            self.dirty_areas[index] = self.dirty_areas[self.dirty_count - 1];
        }
        self.dirty_count -= 1;
    }

    fn mergeBestDirtyPair(self: *Display) void {
        if (self.dirty_count <= 1) return;

        var best_i: usize = 0;
        var best_j: usize = 1;
        var best_cost: i32 = std.math.maxInt(i32);

        var i: usize = 0;
        while (i < self.dirty_count) : (i += 1) {
            var j: usize = i + 1;
            while (j < self.dirty_count) : (j += 1) {
                const merged = Rect.unionRect(self.dirty_areas[i], self.dirty_areas[j]);
                const cost = merged.area() - self.dirty_areas[i].area() - self.dirty_areas[j].area();
                if (cost < best_cost) {
                    best_cost = cost;
                    best_i = i;
                    best_j = j;
                }
            }
        }

        self.dirty_areas[best_i] = Rect.unionRect(self.dirty_areas[best_i], self.dirty_areas[best_j]);
        self.removeDirtyAt(best_j);
    }

    pub fn mergeDirtyAreas(self: *Display) void {
        if (self.dirty_count <= 1) return;

        var changed = true;
        while (changed) {
            changed = false;
            var i: usize = 0;
            while (i < self.dirty_count) : (i += 1) {
                var j: usize = i + 1;
                while (j < self.dirty_count) : (j += 1) {
                    if (shouldMergeDirty(self.dirty_areas[i], self.dirty_areas[j])) {
                        self.dirty_areas[i] = Rect.unionRect(self.dirty_areas[i], self.dirty_areas[j]);
                        self.removeDirtyAt(j);
                        changed = true;
                        break;
                    }
                }
                if (changed) break;
            }
        }
    }

    pub fn render(self: *Display) void {
        if (self.dirty_count == 0) return;

        self.mergeDirtyAreas();

        var i: usize = 0;
        while (i < self.dirty_count) : (i += 1) {
            const dirty = self.dirty_areas[i];
            const chunk_h_max = @divTrunc(@as(i32, @intCast(self.draw_buf.len)), dirty.w);
            if (chunk_h_max <= 0) continue;

            var curr_y = dirty.y;
            const end_y = dirty.y + dirty.h;

            while (curr_y < end_y) {
                const chunk_h = @min(chunk_h_max, end_y - curr_y);
                const chunk_rect = Rect.init(dirty.x, curr_y, dirty.w, chunk_h);

                lcd.waitDmaDone();

                var canvas = Canvas.init(chunk_rect, self.draw_buf[0..@intCast(dirty.w * chunk_h)]);
                canvas.fillRect(chunk_rect.x, chunk_rect.y, chunk_rect.w, chunk_rect.h, default_bg);

                self.renderNodeRecursive(&self.screen, &canvas, chunk_rect);

                canvas.flush();
                curr_y += chunk_h;
            }
        }
        self.dirty_count = 0;
    }

    fn renderNodeRecursive(self: *Display, node: *Node, canvas: *Canvas, clip_rect: Rect) void {
        if (node.hidden) return;

        const abs_area = node.getAbsArea();
        if (Rect.intersect(abs_area, clip_rect)) |draw_clip| {
            const old_clip = canvas.clip;

            canvas.setClip(draw_clip);
            if (node.draw_cb) |draw| {
                draw(node, canvas);
            }

            var child = node.first_child;
            while (child) |c| {
                self.renderNodeRecursive(c, canvas, clip_rect);
                child = c.next;
            }

            canvas.clip = old_clip;
        }
    }
};

fn alignedX(area: Rect, content_w: i32, text_align: Align) i32 {
    return switch (text_align) {
        .left => area.x,
        .center => area.x + @max(0, @divTrunc(area.w - content_w, 2)),
        .right => area.x + @max(0, area.w - content_w),
    };
}

fn absI32(value: i32) i32 {
    return if (value < 0) -value else value;
}
