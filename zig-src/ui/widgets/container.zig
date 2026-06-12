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
