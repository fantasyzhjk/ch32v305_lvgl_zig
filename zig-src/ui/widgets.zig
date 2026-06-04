const std = @import("std");
const Color = @import("color.zig").Color565;
const canvas_mod = @import("canvas.zig");
const core = @import("core.zig");
const types = @import("types.zig");

const Align = types.Align;
const Canvas = canvas_mod.Canvas;
const FontSize = types.FontSize;
const Node = core.Node;
const Rect = types.Rect;

fn optionalColorData(color: ?Color) ?u16 {
    return if (color) |c| c.data else null;
}

fn requiredOption(comptime T: type, args: anytype, comptime name: []const u8) T {
    const Args = @TypeOf(args);
    if (!@hasField(Args, name)) {
        @compileError("missing required UI option: " ++ name);
    }
    return @field(args, name);
}

fn option(comptime T: type, args: anytype, comptime name: []const u8, default: T) T {
    const Args = @TypeOf(args);
    if (@hasField(Args, name)) {
        return @field(args, name);
    }
    return default;
}

pub const Container = struct {
    node: Node,

    pub const Options = struct {
        area: Rect,
    };

    pub fn init(args: anytype) Container {
        const area = requiredOption(Rect, args, "area");
        return .{ .node = Node.init(area.x, area.y, area.w, area.h) };
    }

    pub fn asNode(self: *Container) *Node {
        return &self.node;
    }
};

pub const Panel = struct {
    node: Node,
    bg_color: ?Color = Color.DARKGRAY,
    border_color: ?Color = Color.WHITE,

    pub const Options = struct {
        area: Rect,
        bg_color: ?Color = Color.DARKGRAY,
        border_color: ?Color = Color.WHITE,
    };

    pub fn init(args: anytype) Panel {
        const area = requiredOption(Rect, args, "area");
        var self = Panel{
            .node = Node.init(area.x, area.y, area.w, area.h),
            .bg_color = option(?Color, args, "bg_color", Color.DARKGRAY),
            .border_color = option(?Color, args, "border_color", Color.WHITE),
        };
        self.node.draw_cb = draw;
        return self;
    }

    pub fn asNode(self: *Panel) *Node {
        return &self.node;
    }

    pub fn setBgColor(self: *Panel, bg_color: ?Color) void {
        if (optionalColorData(self.bg_color) == optionalColorData(bg_color)) return;
        self.bg_color = bg_color;
        self.node.invalidate();
    }

    pub fn setBorderColor(self: *Panel, border_color: ?Color) void {
        if (optionalColorData(self.border_color) == optionalColorData(border_color)) return;
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

    pub const Options = struct {
        area: Rect,
        color: Color = Color.WHITE,
        x1: i32 = 0,
        y1: i32 = 0,
        x2: ?i32 = null,
        y2: ?i32 = null,
    };

    pub fn init(args: anytype) Line {
        const area = requiredOption(Rect, args, "area");
        var self = Line{
            .node = Node.init(area.x, area.y, area.w, area.h),
            .x1 = option(i32, args, "x1", 0),
            .y1 = option(i32, args, "y1", 0),
            .x2 = option(?i32, args, "x2", null) orelse @max(0, area.w - 1),
            .y2 = option(?i32, args, "y2", null) orelse @max(0, area.h - 1),
            .color = option(Color, args, "color", Color.WHITE),
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
    font: FontSize = .px16,
    text_align: Align = .left,

    pub const Options = struct {
        area: Rect,
        text: []const u8,
        color: Color = Color.WHITE,
        bg_color: ?Color = null,
        font: FontSize = .px16,
        text_align: Align = .left,
    };

    pub fn init(args: anytype) Label {
        const area = requiredOption(Rect, args, "area");
        var self = Label{
            .node = Node.init(area.x, area.y, area.w, area.h),
            .text = requiredOption([]const u8, args, "text"),
            .color = option(Color, args, "color", Color.WHITE),
            .bg_color = option(?Color, args, "bg_color", null),
            .font = option(FontSize, args, "font", .px16),
            .text_align = option(Align, args, "text_align", .left),
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
        if (optionalColorData(self.bg_color) == optionalColorData(bg_color)) return;
        self.bg_color = bg_color;
        self.node.invalidate();
    }

    pub fn setFont(self: *Label, font_size: FontSize) void {
        if (self.font == font_size) return;
        self.font = font_size;
        self.node.invalidate();
    }

    pub fn setAlign(self: *Label, text_align: Align) void {
        if (self.text_align == text_align) return;
        self.text_align = text_align;
        self.node.invalidate();
    }

    fn draw(node: *Node, canvas: *Canvas) void {
        const self: *Label = @fieldParentPtr("node", node);
        const abs = node.getAbsArea();
        if (self.bg_color) |bg| {
            canvas.fillRect(abs.x, abs.y, abs.w, abs.h, bg);
        }

        const size = types.textSize(self.font, self.text);
        const x = types.alignedX(abs, size.w, self.text_align);
        const y = abs.y + @max(0, @divTrunc(abs.h - size.h, 2));
        canvas.showString(x, y, self.font, self.text, self.color, self.bg_color);
    }
};

pub const MarqueeLabel = struct {
    node: Node,
    text: []const u8,
    color: Color = Color.WHITE,
    bg_color: ?Color = null,
    font: FontSize = .px16,
    offset: i32,
    gap: i32 = 16,

    pub const Options = struct {
        area: Rect,
        text: []const u8,
        color: Color = Color.WHITE,
        bg_color: ?Color = null,
        font: FontSize = .px16,
        offset: ?i32 = null,
        gap: i32 = 16,
    };

    pub fn init(args: anytype) MarqueeLabel {
        const area = requiredOption(Rect, args, "area");
        var self = MarqueeLabel{
            .node = Node.init(area.x, area.y, area.w, area.h),
            .text = requiredOption([]const u8, args, "text"),
            .color = option(Color, args, "color", Color.WHITE),
            .bg_color = option(?Color, args, "bg_color", null),
            .font = option(FontSize, args, "font", .px16),
            .offset = option(?i32, args, "offset", null) orelse area.w,
            .gap = option(i32, args, "gap", 16),
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
        if (optionalColorData(self.bg_color) == optionalColorData(bg_color)) return;
        self.bg_color = bg_color;
        self.node.invalidate();
    }

    pub fn setFont(self: *MarqueeLabel, font_size: FontSize) void {
        if (self.font == font_size) return;
        self.node.invalidate();
        self.font = font_size;
        self.offset = self.wrapOffset(self.offset);
        self.node.invalidate();
    }

    fn wrapOffset(self: *const MarqueeLabel, offset: i32) i32 {
        const text_w = types.textSize(self.font, self.text).w;
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

        const size = types.textSize(self.font, self.text);
        if (size.w <= 0 or size.h <= 0) return;

        const y = abs.y + @max(0, @divTrunc(abs.h - size.h, 2));
        const stride: i32 = @max(@as(i32, 1), size.w + self.gap);
        var x = abs.x + self.offset;

        while (x > abs.x - stride) {
            x -= stride;
        }
        while (x < abs.x + abs.w) {
            canvas.showString(x, y, self.font, self.text, self.color, self.bg_color);
            x += stride;
        }
    }
};

pub const Button = struct {
    node: Node,
    text: []const u8,
    font: FontSize = .px16,
    text_color: Color = Color.WHITE,
    bg_color: Color = Color.BLUE,
    pressed_bg_color: Color = Color.DARKGRAY,
    disabled_bg_color: Color = Color.LGRAY,
    border_color: Color = Color.WHITE,
    pressed: bool = false,
    enabled: bool = true,

    pub const Options = struct {
        area: Rect,
        text: []const u8,
        font: FontSize = .px16,
        text_color: Color = Color.WHITE,
        bg_color: Color = Color.BLUE,
        pressed_bg_color: Color = Color.DARKGRAY,
        disabled_bg_color: Color = Color.LGRAY,
        border_color: Color = Color.WHITE,
        pressed: bool = false,
        enabled: bool = true,
    };

    pub fn init(args: anytype) Button {
        const area = requiredOption(Rect, args, "area");
        var self = Button{
            .node = Node.init(area.x, area.y, area.w, area.h),
            .text = requiredOption([]const u8, args, "text"),
            .font = option(FontSize, args, "font", .px16),
            .text_color = option(Color, args, "text_color", Color.WHITE),
            .bg_color = option(Color, args, "bg_color", Color.BLUE),
            .pressed_bg_color = option(Color, args, "pressed_bg_color", Color.DARKGRAY),
            .disabled_bg_color = option(Color, args, "disabled_bg_color", Color.LGRAY),
            .border_color = option(Color, args, "border_color", Color.WHITE),
            .pressed = option(bool, args, "pressed", false),
            .enabled = option(bool, args, "enabled", true),
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

        const size = types.textSize(self.font, self.text);
        const x = types.alignedX(abs, size.w, .center);
        const y = abs.y + @max(0, @divTrunc(abs.h - size.h, 2));
        canvas.showString(x, y, self.font, self.text, self.text_color, bg);
    }
};

pub const Image = struct {
    node: Node,
    pixels: []const u16 = &.{},
    stride: i32 = 0,
    color_key: ?u16 = null,
    bg_color: ?Color = null,

    pub const Options = struct {
        area: Rect,
        pixels: []const u16 = &.{},
        stride: ?i32 = null,
        color_key: ?u16 = null,
        bg_color: ?Color = null,
    };

    pub fn init(args: anytype) Image {
        const area = requiredOption(Rect, args, "area");
        var self = Image{
            .node = Node.init(area.x, area.y, area.w, area.h),
            .pixels = option([]const u16, args, "pixels", &.{}),
            .stride = option(?i32, args, "stride", null) orelse area.w,
            .color_key = option(?u16, args, "color_key", null),
            .bg_color = option(?Color, args, "bg_color", null),
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
