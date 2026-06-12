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
