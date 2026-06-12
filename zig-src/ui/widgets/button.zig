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
