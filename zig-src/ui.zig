const std = @import("std");
const lcd = @import("lcd.zig");
const font = @import("font.zig");
const Color = @import("color.zig").Color565;

pub const Rect = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,

    pub fn unionRect(a: Rect, b: Rect) Rect {
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
        const x1 = @max(a.x, b.x);
        const y1 = @max(a.y, b.y);
        const x2 = @min(a.x + a.w, b.x + b.w);
        const y2 = @min(a.y + a.h, b.y + b.h);

        if (x1 < x2 and y1 < y2) {
            return Rect{
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
};

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
        if (Rect.intersect(self.area, clip)) |res| {
            self.clip = res;
        } else {
            self.clip = .{ .x = 0, .y = 0, .w = 0, .h = 0 };
        }
    }

    pub fn drawPoint(self: *Canvas, x: i32, y: i32, color: Color) void {
        if (self.clip.contains(x, y)) {
            const lx = x - self.area.x;
            const ly = y - self.area.y;
            if (lx >= 0 and lx < self.area.w and ly >= 0 and ly < self.area.h) {
                self.buf[@as(usize, @intCast(ly)) * @as(usize, @intCast(self.area.w)) + @as(usize, @intCast(lx))] = color.toRgb565();
            }
        }
    }

    pub fn fillRect(self: *Canvas, x: i32, y: i32, w: i32, h: i32, color: Color) void {
        const draw_rect = Rect{ .x = x, .y = y, .w = w, .h = h };
        if (Rect.intersect(draw_rect, self.clip)) |res| {
            const raw_color = color.toRgb565();
            var iy = res.y;
            while (iy < res.y + res.h) : (iy += 1) {
                var ix = res.x;
                while (ix < res.x + res.w) : (ix += 1) {
                    const lx = ix - self.area.x;
                    const ly = iy - self.area.y;
                    if (lx >= 0 and lx < self.area.w and ly >= 0 and ly < self.area.h) {
                        self.buf[@as(usize, @intCast(ly)) * @as(usize, @intCast(self.area.w)) + @as(usize, @intCast(lx))] = raw_color;
                    }
                }
            }
        }
    }

    pub fn drawRect(self: *Canvas, x: i32, y: i32, w: i32, h: i32, color: Color) void {
        const rect = Rect{ .x = x, .y = y, .w = w, .h = h };
        if (Rect.intersect(rect, self.clip) == null) return;

        var i: i32 = 0;
        while (i < w) : (i += 1) {
            self.drawPoint(x + i, y, color);
            self.drawPoint(x + i, y + h - 1, color);
        }
        i = 0;
        while (i < h) : (i += 1) {
            self.drawPoint(x, y + i, color);
            self.drawPoint(x + w - 1, y + i, color);
        }
    }

    pub fn drawLine(self: *Canvas, x1: i32, y1: i32, x2: i32, y2: i32, color: Color) void {
        const adx = if (x1 > x2) x1 - x2 else x2 - x1;
        const ady = if (y1 > y2) y1 - y2 else y2 - y1;
        const line_rect = Rect{
            .x = @min(x1, x2),
            .y = @min(y1, y2),
            .w = adx + 1,
            .h = ady + 1,
        };
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

        var xerr: i32 = 0;
        var yerr: i32 = 0;
        var i: i32 = 0;
        while (i <= distance) : (i += 1) {
            self.drawPoint(row, col, color);
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
        const circle_rect = Rect{ .x = x0 - r, .y = y0 - r, .w = r * 2 + 1, .h = r * 2 + 1 };
        if (Rect.intersect(circle_rect, self.clip) == null) return;

        var a: i32 = 0;
        var b: i32 = r;
        var di: i32 = 3 - r * 2;

        while (a <= b) {
            self.drawPoint(x0 + a, y0 - b, color);
            self.drawPoint(x0 + b, y0 - a, color);
            self.drawPoint(x0 + b, y0 + a, color);
            self.drawPoint(x0 + a, y0 + b, color);
            self.drawPoint(x0 - a, y0 + b, color);
            self.drawPoint(x0 - b, y0 + a, color);
            self.drawPoint(x0 - b, y0 - a, color);
            self.drawPoint(x0 - a, y0 - b, color);

            a += 1;
            if (di < 0) {
                di += 4 * a + 6;
            } else {
                di += 10 + 4 * (a - b);
                b -= 1;
            }
        }
    }

    pub fn showChar(self: *Canvas, x_off: i32, y_off: i32, ch: u8, size: u32, color: Color, bg_color: ?Color) void {
        if (ch < 0x20 or ch > 0x7e) return;

        const w: i32 = switch (size) {
            12 => 6,
            16 => 8,
            24 => 12,
            else => return,
        };
        const h: i32 = @intCast(size);

        const char_rect = Rect{ .x = x_off, .y = y_off, .w = w, .h = h };
        if (Rect.intersect(char_rect, self.clip) == null) return;

        const idx: usize = @as(usize, ch - 0x20);

        var row: i32 = 0;
        while (row < h) : (row += 1) {
            var col: i32 = 0;
            while (col < w) : (col += 1) {
                const urow: u16 = @intCast(row);
                const ucol: u16 = @intCast(col);
                const lit = switch (size) {
                    12 => blk: {
                        const val = (@as(u16, font.asc2_1206[idx][ucol * 2]) << 8) | @as(u16, font.asc2_1206[idx][ucol * 2 + 1]);
                        const bit_pos: u4 = @intCast(15 - urow);
                        break :blk ((val >> bit_pos) & 1) != 0;
                    },
                    16 => blk: {
                        const val = (@as(u16, font.asc2_1608[idx][ucol * 2]) << 8) | @as(u16, font.asc2_1608[idx][ucol * 2 + 1]);
                        const bit_pos: u4 = @intCast(15 - urow);
                        break :blk ((val >> bit_pos) & 1) != 0;
                    },
                    24 => blk: {
                        const val = (@as(u32, font.asc2_2412[idx][ucol * 3]) << 16) |
                            (@as(u32, font.asc2_2412[idx][ucol * 3 + 1]) << 8) |
                            @as(u32, font.asc2_2412[idx][ucol * 3 + 2]);
                        const bit_pos: u5 = @intCast(23 - urow);
                        break :blk ((val >> bit_pos) & 1) != 0;
                    },
                    else => false,
                };
                if (lit) {
                    self.drawPoint(x_off + col, y_off + row, color);
                } else if (bg_color) |bg| {
                    self.drawPoint(x_off + col, y_off + row, bg);
                }
            }
        }
    }

    pub fn showString(self: *Canvas, x_off: i32, y_off: i32, size: u32, str: []const u8, color: Color, bg_color: ?Color) void {
        const w: i32 = switch (size) {
            12 => 6,
            16 => 8,
            24 => 12,
            else => return,
        };
        var cx = x_off;
        var cy = y_off;
        for (str) |ch| {
            if (ch == '\n') {
                cx = x_off;
                cy += @intCast(size);
                continue;
            }
            self.showChar(cx, cy, ch, size, color, bg_color);
            cx += w;
        }
    }

    pub fn flush(self: *Canvas) void {
        lcd.flushPixels(@intCast(self.area.x), @intCast(self.area.y), @intCast(self.area.x + self.area.w - 1), @intCast(self.area.y + self.area.h - 1), self.buf.ptr);
    }
};

pub const Node = struct {
    area: Rect,
    parent: ?*Node = null,
    first_child: ?*Node = null,
    last_child: ?*Node = null,
    next: ?*Node = null,
    prev: ?*Node = null,
    draw_cb: ?*const fn (node: *Node, canvas: *Canvas) void = null,

    pub fn init(x: i32, y: i32, w: i32, h: i32) Node {
        return .{
            .area = .{ .x = x, .y = y, .w = w, .h = h },
        };
    }

    pub fn getAbsArea(self: *Node) Rect {
        var abs_area = self.area;
        var p = self.parent;
        while (p) |par| {
            abs_area.x += par.area.x;
            abs_area.y += par.area.y;
            p = par.parent;
        }
        return abs_area;
    }

    pub fn addChild(self: *Node, child: *Node) void {
        child.parent = self;
        if (self.last_child) |last| {
            last.next = child;
            child.prev = last;
            self.last_child = child;
        } else {
            self.first_child = child;
            self.last_child = child;
        }
        self.invalidate();
    }

    pub fn removeChild(self: *Node, child: *Node) void {
        if (child.prev) |p| p.next = child.next else self.first_child = child.next;
        if (child.next) |n| n.prev = child.prev else self.last_child = child.prev;
        child.parent = null;
        child.next = null;
        child.prev = null;
        self.invalidate();
    }

    pub fn setPos(self: *Node, x: i32, y: i32) void {
        if (self.area.x == x and self.area.y == y) return;
        self.invalidate();
        self.area.x = x;
        self.area.y = y;
        self.invalidate();
    }

    pub fn invalidate(self: *Node) void {
        const abs_area = self.getAbsArea();
        if (Display.current) |disp| {
            disp.markDirty(abs_area);
        }
    }
};

pub const Display = struct {
    screen: Node,
    dirty_areas: [16]Rect = undefined,
    dirty_count: usize = 0,
    draw_buf: []u16,
    allocator: std.mem.Allocator,

    pub var current: ?*Display = null;

    /// Initialize a Display.
    /// allocator: Used for allocating the draw buffer and nodes.
    /// buffer_height: The height of the partial refresh buffer (width is always lcd.WIDTH).
    pub fn init(allocator: std.mem.Allocator, buffer_height: u32) !Display {
        const buf_len = @as(usize, lcd.WIDTH) * buffer_height;
        const buf = try allocator.alloc(u16, buf_len);

        return Display{
            .screen = Node.init(0, 0, lcd.WIDTH, lcd.HEIGHT),
            .draw_buf = buf,
            .allocator = allocator,
        };
    }

    /// Bind this display as the current active one.
    pub fn bind(self: *Display) void {
        current = self;
        self.markDirty(self.screen.area);
    }

    /// Create a new UI node using the display's allocator.
    pub fn createNode(self: *Display, x: i32, y: i32, w: i32, h: i32, draw_cb: ?*const fn (node: *Node, canvas: *Canvas) void) !*Node {
        const node = try self.allocator.create(Node);
        node.* = Node.init(x, y, w, h);
        node.draw_cb = draw_cb;
        return node;
    }

    /// Add a child to the root screen.
    pub fn screenAddChild(self: *Display, child: *Node) void {
        self.screen.addChild(child);
    }

    pub fn markDirty(self: *Display, rect: Rect) void {
        const screen_rect = self.screen.area;
        const bounded = Rect.intersect(rect, screen_rect) orelse return;

        if (self.dirty_count < self.dirty_areas.len) {
            self.dirty_areas[self.dirty_count] = bounded;
            self.dirty_count += 1;
        } else {
            var union_all = self.dirty_areas[0];
            for (self.dirty_areas[1..]) |r| {
                union_all = Rect.unionRect(union_all, r);
            }
            union_all = Rect.unionRect(union_all, bounded);
            self.dirty_areas[0] = union_all;
            self.dirty_count = 1;
        }
    }

    fn mergeDirtyAreas(self: *Display) void {
        if (self.dirty_count <= 1) return;

        var changed = true;
        while (changed) {
            changed = false;
            var i: usize = 0;
            while (i < self.dirty_count) : (i += 1) {
                var j: usize = i + 1;
                while (j < self.dirty_count) : (j += 1) {
                    if (Rect.intersect(self.dirty_areas[i], self.dirty_areas[j]) != null) {
                        self.dirty_areas[i] = Rect.unionRect(self.dirty_areas[i], self.dirty_areas[j]);
                        if (j < self.dirty_count - 1) {
                            self.dirty_areas[j] = self.dirty_areas[self.dirty_count - 1];
                        }
                        self.dirty_count -= 1;
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
                const chunk_rect = Rect{ .x = dirty.x, .y = curr_y, .w = dirty.w, .h = chunk_h };

                // CRITICAL: Wait for previous DMA to finish before we start overwriting the shared draw_buf
                lcd.waitDmaDone();

                var canvas = Canvas.init(chunk_rect, self.draw_buf[0..@intCast(dirty.w * chunk_h)]);
                canvas.fillRect(chunk_rect.x, chunk_rect.y, chunk_rect.w, chunk_rect.h, Color.BLACK);

                self.renderNodeRecursive(&self.screen, &canvas, chunk_rect);

                canvas.flush();
                curr_y += chunk_h;
            }
        }
        self.dirty_count = 0;
    }

    fn renderNodeRecursive(self: *Display, node: *Node, canvas: *Canvas, clip_rect: Rect) void {
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
