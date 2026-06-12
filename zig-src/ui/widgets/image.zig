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
