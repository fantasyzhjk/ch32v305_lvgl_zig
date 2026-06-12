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
