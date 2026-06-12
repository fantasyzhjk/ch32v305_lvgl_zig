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

pub const List = struct {
    node: Node,
    items: []const Item,
    font: FontSize = .px16,
    text_color: Color = Color.WHITE,
    bg_color: Color = Color.DARKGRAY,
    selected_bg_color: Color = Color.LGRAY,
    border_color: Color = Color.WHITE,
    select_index: usize = 0,
    target_rect_pos: i32 = 0,
    last_rect_pos: i32 = 0,

    pub const Item = struct { tag: []const u8, discption: ?[]const u8, ref: ?*const fn () void };

    pub const Options = struct {
        node: Node,
        items: []const Item,
        font: FontSize = .px16,
        text_color: Color = Color.WHITE,
        bg_color: Color = Color.BLUE,
        selected_bg_color: Color = Color.DARKGRAY,
        border_color: Color = Color.WHITE,
        select_index: usize = 0,
    };

    pub fn init(args: anytype) List {
        const area = requiredOption(Rect, args, "area");
        var self = List{
            .node = Node.init(area.x, area.y, area.w, area.h),
            .items = requiredOption([]const Item, args, "items"),
            .font = option(FontSize, args, "font", .px16),
            .text_color = option(Color, args, "text_color", Color.WHITE),
            .bg_color = option(Color, args, "bg_color", Color.BLUE),
            .selected_bg_color = option(Color, args, "selected_bg_color", Color.DARKGRAY),
            .border_color = option(Color, args, "border_color", Color.WHITE),
            .select_index = option(usize, args, "select_index", 0),
        };
        self.node.draw_cb = draw;
        self.select(0);
        return self;
    }

    pub fn asNode(self: *List) *Node {
        return &self.node;
    }

    pub fn select(self: *List, index: usize) void {
        if (index == self.select_index) return;
        if (index > self.items.len) return;
        if (index < 0) return;
        self.select_index = index;

        const abs = self.node.getAbsArea();
        const line_hight = @divTrunc(abs.h, @as(i32, @intCast(self.items.len)));
        self.target_rect_pos = abs.y + 2 + (@as(i32, @intCast(index)) * line_hight);
    }

    pub fn update(self: *List) void {
        if (self.target_rect_pos != self.last_rect_pos) {
            self.last_rect_pos = utils.lerp(i32, self.last_rect_pos, self.target_rect_pos, 0.3);
            self.node.invalidate();
        }
    }

    fn draw(node: *Node, canvas: *Canvas) void {
        const self: *List = @fieldParentPtr("node", node);
        const abs = node.getAbsArea();
        canvas.fillRect(abs.x, abs.y, abs.w, abs.h, self.bg_color);
        const line_hight = @divTrunc(abs.h, @as(i32, @intCast(self.items.len)));
        canvas.fillRect(abs.x, self.last_rect_pos, abs.w, line_hight, self.selected_bg_color);
        for (self.items, 0..) |value, i| {
            const ly = @as(i32, @intCast(i)) * line_hight;
            const size = types.textSize(self.font, value.tag);
            const x = types.alignedX(abs, size.w, .center);
            const y = abs.y + ly + @max(0, @divTrunc(line_hight - size.h, 2));
            canvas.showString(x, y, self.font, value.tag, self.text_color, null);
        }
        canvas.drawRect(abs.x, abs.y, abs.w, abs.h, self.border_color);
    }
};
