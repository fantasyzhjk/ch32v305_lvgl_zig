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
