const std = @import("std");
const lcd = @import("../lcd.zig");
const Color = @import("color.zig").Color565;
const canvas_mod = @import("canvas.zig");
const types = @import("types.zig");

const Canvas = canvas_mod.Canvas;
const Rect = types.Rect;

const dirty_max_areas = 16;
const dirty_merge_slack = 1;
const dirty_merge_waste_min = 64;
const default_bg = Color.BLACK;

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

pub const Display = struct {
    pub const PostRenderFn = *const fn (buf: []u16, buf_w: i32, rect: Rect) void;

    screen: Node,
    dirty_areas: [dirty_max_areas]Rect = undefined,
    dirty_count: usize = 0,
    draw_buf: []u16, // double-sized: 2 * WIDTH * buffer_height
    buffer_height: u32, // chunk height (half of draw_buf rows)
    allocator: std.mem.Allocator,

    active_buf: u1 = 0,
    post_render: ?PostRenderFn = null,

    pub var current: ?*Display = null;

    pub fn init(allocator: std.mem.Allocator, buffer_height: u32) !Display {
        const buf_len = @as(usize, lcd.WIDTH) * buffer_height * 2; // double buffer
        const buf = try allocator.alloc(u16, buf_len);

        return .{
            .screen = Node.init(0, 0, lcd.WIDTH, lcd.HEIGHT),
            .draw_buf = buf,
            .buffer_height = buffer_height,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Display) void {
        self.allocator.free(self.draw_buf);
        if (current == self) current = null;
    }

    fn activeBuf(self: *Display) []u16 {
        const len = @as(usize, lcd.WIDTH) * self.buffer_height;
        return self.draw_buf[self.active_buf *% len ..][0..len];
    }

    pub fn bind(self: *Display) void {
        current = self;
        self.screen.setDisplayRecursive(self);
        self.markDirty(self.screen.area);
    }

    pub fn create(self: *Display, comptime T: type, args: anytype) !*T {
        comptime validateWidget(T);

        const item = try self.allocator.create(T);
        item.* = T.init(args);
        item.asNode().setDisplayRecursive(self);
        return item;
    }

    pub fn add(self: *Display, parent: anytype, comptime T: type, args: anytype) !*T {
        const item = try self.create(T, args);
        nodeFrom(parent).addChild(item.asNode());
        return item;
    }

    pub fn addToScreen(self: *Display, comptime T: type, args: anytype) !*T {
        const item = try self.create(T, args);
        self.screen.addChild(item.asNode());
        return item;
    }

    pub fn createNode(self: *Display, x: i32, y: i32, w: i32, h: i32, draw_cb: ?*const fn (node: *Node, canvas: *Canvas) void) !*Node {
        const node = try self.allocator.create(Node);
        node.* = Node.init(x, y, w, h);
        node.display = self;
        node.draw_cb = draw_cb;
        return node;
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

        const chunk_h_max = @as(i32, @intCast(self.buffer_height));
        const buf_len = @as(usize, @intCast(chunk_h_max)) * lcd.WIDTH;

        var i: usize = 0;
        while (i < self.dirty_count) : (i += 1) {
            const dirty = self.dirty_areas[i];
            if (chunk_h_max <= 0) continue;

            var curr_y = dirty.y;
            const end_y = dirty.y + dirty.h;

            while (curr_y < end_y) {
                const chunk_h = @min(chunk_h_max, end_y - curr_y);
                const chunk_rect = Rect.init(dirty.x, curr_y, dirty.w, chunk_h);

                // CPU renders while previous DMA is still transferring
                var canvas = Canvas.init(chunk_rect, self.activeBuf()[0..buf_len]);
                canvas.fillRect(chunk_rect.x, chunk_rect.y, chunk_rect.w, chunk_rect.h, default_bg);
                self.renderNodeRecursive(&self.screen, &canvas, chunk_rect);

                if (self.post_render) |cb| {
                    cb(canvas.buf[0..buf_len], canvas.area.w, canvas.area);
                }

                lcd.waitDmaDone();
                canvas.flush();

                self.active_buf +%= 1;
                curr_y += chunk_h;
            }
        }
        self.dirty_count = 0;
        lcd.present();
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
                self.renderNodeRecursive(c, canvas, draw_clip);
                child = c.next;
            }

            canvas.clip = old_clip;
        }
    }
};

fn validateWidget(comptime T: type) void {
    if (!@hasDecl(T, "Options")) {
        @compileError(@typeName(T) ++ " must declare pub const Options");
    }
    if (!@hasDecl(T, "init")) {
        @compileError(@typeName(T) ++ " must declare pub fn init(options: Options)");
    }
    if (!@hasDecl(T, "asNode")) {
        @compileError(@typeName(T) ++ " must declare pub fn asNode(self: *Self) *ui.Node");
    }
}

fn nodeFrom(parent: anytype) *Node {
    const Parent = @TypeOf(parent);
    if (Parent == *Node) return parent;

    switch (@typeInfo(Parent)) {
        .pointer => |ptr| {
            if (@hasDecl(ptr.child, "asNode")) return parent.asNode();
        },
        else => {},
    }

    @compileError("parent must be *ui.Node or a pointer to a widget with asNode()");
}
