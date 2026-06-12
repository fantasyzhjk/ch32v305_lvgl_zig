const std = @import("std");
const ui = @import("../ui.zig");
const types = @import("../types.zig");
const core = @import("core.zig");
const utils = @import("../../utils.zig");

const Color = ui.Color565;
const Align = ui.Align;
const Canvas = ui.Canvas;
const FontSize = ui.FontSize;
const Node = ui.Node;
const Rect = ui.Rect;
const requiredOption = core.requiredOption;
const option = core.option;
const optionalColorData = core.optionalColorData;

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
