const std = @import("std");
const Color = @import("color.zig").Color565;
const canvas_mod = @import("canvas.zig");
const core = @import("core.zig");
const types = @import("types.zig");

const Align = types.Align;
const Canvas = canvas_mod.Canvas;
const Node = core.Node;

pub const Container = struct {
    node: Node,

    pub fn init(x: i32, y: i32, w: i32, h: i32) Container {
        return .{ .node = Node.init(x, y, w, h) };
    }

    pub fn asNode(self: *Container) *Node {
        return &self.node;
    }
};

pub const Panel = struct {
    node: Node,
    bg_color: ?Color = Color.DARKGRAY,
    border_color: ?Color = Color.WHITE,

    pub fn init(x: i32, y: i32, w: i32, h: i32) Panel {
        var self = Panel{
            .node = Node.init(x, y, w, h),
        };
        self.node.draw_cb = draw;
        return self;
    }

    pub fn asNode(self: *Panel) *Node {
        return &self.node;
    }

    pub fn setBgColor(self: *Panel, bg_color: ?Color) void {
        const old = if (self.bg_color) |c| c.data else null;
        const new = if (bg_color) |c| c.data else null;
        if (old == new) return;
        self.bg_color = bg_color;
        self.node.invalidate();
    }

    pub fn setBorderColor(self: *Panel, border_color: ?Color) void {
        const old = if (self.border_color) |c| c.data else null;
        const new = if (border_color) |c| c.data else null;
        if (old == new) return;
        self.border_color = border_color;
        self.node.invalidate();
    }

    fn draw(node: *Node, canvas: *Canvas) void {
        const self: *Panel = @fieldParentPtr("node", node);
        const abs = node.getAbsArea();
        if (self.bg_color) |bg| {
            canvas.fillRect(abs.x, abs.y, abs.w, abs.h, bg);
        }
        if (self.border_color) |border| {
            canvas.drawRect(abs.x, abs.y, abs.w, abs.h, border);
        }
    }
};

pub const Box = Panel;

pub const Line = struct {
    node: Node,
    x1: i32 = 0,
    y1: i32 = 0,
    x2: i32,
    y2: i32,
    color: Color,

    pub fn init(x: i32, y: i32, w: i32, h: i32, color: Color) Line {
        var self = Line{
            .node = Node.init(x, y, w, h),
            .x2 = @max(0, w - 1),
            .y2 = @max(0, h - 1),
            .color = color,
        };
        self.node.draw_cb = draw;
        return self;
    }

    pub fn asNode(self: *Line) *Node {
        return &self.node;
    }

    pub fn setPoints(self: *Line, x1: i32, y1: i32, x2: i32, y2: i32) void {
        if (self.x1 == x1 and self.y1 == y1 and self.x2 == x2 and self.y2 == y2) return;
        self.x1 = x1;
        self.y1 = y1;
        self.x2 = x2;
        self.y2 = y2;
        self.node.invalidate();
    }

    pub fn setColor(self: *Line, color: Color) void {
        if (self.color.data == color.data) return;
        self.color = color;
        self.node.invalidate();
    }

    fn draw(node: *Node, canvas: *Canvas) void {
        const self: *Line = @fieldParentPtr("node", node);
        const abs = node.getAbsArea();
        canvas.drawLine(abs.x + self.x1, abs.y + self.y1, abs.x + self.x2, abs.y + self.y2, self.color);
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

        const size = types.textSize(self.font_size, self.text);
        const x = types.alignedX(abs, size.w, self.text_align);
        const y = abs.y + @max(0, @divTrunc(abs.h - size.h, 2));
        canvas.showString(x, y, self.font_size, self.text, self.color, self.bg_color);
    }
};

pub const MarqueeLabel = struct {
    node: Node,
    text: []const u8,
    color: Color = Color.WHITE,
    bg_color: ?Color = null,
    font_size: u32 = 16,
    offset: i32,
    gap: i32 = 16,

    pub fn init(x: i32, y: i32, w: i32, h: i32, text: []const u8) MarqueeLabel {
        var self = MarqueeLabel{
            .node = Node.init(x, y, w, h),
            .text = text,
            .offset = w,
        };
        self.node.draw_cb = draw;
        return self;
    }

    pub fn asNode(self: *MarqueeLabel) *Node {
        return &self.node;
    }

    pub fn setText(self: *MarqueeLabel, text: []const u8) void {
        if (std.mem.eql(u8, self.text, text)) return;
        self.node.invalidate();
        self.text = text;
        self.offset = self.wrapOffset(self.offset);
        self.node.invalidate();
    }

    pub fn setOffset(self: *MarqueeLabel, offset: i32) void {
        const wrapped = self.wrapOffset(offset);
        if (self.offset == wrapped) return;
        self.offset = wrapped;
        self.node.invalidate();
    }

    pub fn step(self: *MarqueeLabel, delta: i32) void {
        self.setOffset(self.offset + delta);
    }

    pub fn setColor(self: *MarqueeLabel, color: Color) void {
        if (self.color.data == color.data) return;
        self.color = color;
        self.node.invalidate();
    }

    pub fn setBgColor(self: *MarqueeLabel, bg_color: ?Color) void {
        const old = if (self.bg_color) |c| c.data else null;
        const new = if (bg_color) |c| c.data else null;
        if (old == new) return;
        self.bg_color = bg_color;
        self.node.invalidate();
    }

    fn wrapOffset(self: *const MarqueeLabel, offset: i32) i32 {
        const text_w = types.textSize(self.font_size, self.text).w;
        const stride: i32 = @max(@as(i32, 1), text_w + self.gap);
        var wrapped = offset;
        while (wrapped < -stride) {
            wrapped += stride;
        }
        while (wrapped > self.node.area.w) {
            wrapped -= stride;
        }
        return wrapped;
    }

    fn draw(node: *Node, canvas: *Canvas) void {
        const self: *MarqueeLabel = @fieldParentPtr("node", node);
        const abs = node.getAbsArea();
        if (self.bg_color) |bg| {
            canvas.fillRect(abs.x, abs.y, abs.w, abs.h, bg);
        }

        const size = types.textSize(self.font_size, self.text);
        if (size.w <= 0 or size.h <= 0) return;

        const y = abs.y + @max(0, @divTrunc(abs.h - size.h, 2));
        const stride: i32 = @max(@as(i32, 1), size.w + self.gap);
        var x = abs.x + self.offset;

        while (x > abs.x - stride) {
            x -= stride;
        }
        while (x < abs.x + abs.w) {
            canvas.showString(x, y, self.font_size, self.text, self.color, self.bg_color);
            x += stride;
        }
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

        const size = types.textSize(self.font_size, self.text);
        const x = types.alignedX(abs, size.w, .center);
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
