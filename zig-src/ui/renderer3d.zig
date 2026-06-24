const std = @import("std");
const font = @import("font.zig");
const Color = @import("color.zig").Color565;
const types = @import("types.zig");
const core = @import("core.zig");
const canvas_mod = @import("canvas.zig");

const Point3D = types.Point3D;
const TexVertex = types.TexVertex;
const FontSize = types.FontSize;
const Rect = types.Rect;
const Node = core.Node;
const Canvas = canvas_mod.Canvas;

pub const Renderer3D = struct {
    // UI 节点（嵌入 widget 树，受脏区域管理）
    node: Node,

    // 相机参数
    fov: f32 = 60.0,
    camera_dist: f32 = 30.0,
    yaw: f32 = 0.0,
    pitch: f32 = 0.0,

    // 帧缓冲绑定（每帧由 draw_cb 从 Canvas 同步）
    area: Rect = Rect.init(0, 0, 0, 0),
    buf: []u16 = &[_]u16{},
    clip: Rect = Rect.init(0, 0, 0, 0),

    // 脏区域追踪：上一帧的紧致包围盒
    old_bb: Rect = Rect.init(0, 0, 0, 0),
    has_old_bb: bool = false,

    // 用户自定义绘制回调
    user_draw: ?*const fn (renderer: *Renderer3D, canvas: *Canvas) void = null,
    user_data: ?*anyopaque = null,

    pub const Options = struct {
        area: Rect,
        fov: f32 = 60.0,
        camera_dist: f32 = 30.0,
    };

    pub fn init(args: anytype) Renderer3D {
        const area = args.area;
        var self = Renderer3D{
            .node = Node.init(area.x, area.y, area.w, area.h),
            .fov = if (@hasField(@TypeOf(args), "fov")) args.fov else 60.0,
            .camera_dist = if (@hasField(@TypeOf(args), "camera_dist")) args.camera_dist else 30.0,
        };
        self.node.draw_cb = drawCb;
        return self;
    }

    pub fn asNode(self: *Renderer3D) *Node {
        return &self.node;
    }

    /// 投影网格顶点到 mesh.projected
    pub fn projectMesh(self: *Renderer3D, mesh: *types.Mesh) void {
        const abs = self.node.getAbsArea();
        const cx = @as(f32, @floatFromInt(abs.x + @divTrunc(abs.w, 2)));
        const cy = @as(f32, @floatFromInt(abs.y + @divTrunc(abs.h, 2)));
        self.projectAll(mesh.vertices, mesh.projected, cx, cy);
    }

    /// 从已投影的 mesh.projected 计算紧致包围盒（屏幕空间）
    pub fn computeBounds(_: *Renderer3D, projected: []const TexVertex) Rect {
        var min_x: f32 = projected[0].x;
        var max_x: f32 = projected[0].x;
        var min_y: f32 = projected[0].y;
        var max_y: f32 = projected[0].y;
        for (projected[1..]) |v| {
            if (v.x < min_x) min_x = v.x;
            if (v.x > max_x) max_x = v.x;
            if (v.y < min_y) min_y = v.y;
            if (v.y > max_y) max_y = v.y;
        }

        // 向外扩展 1 像素，补偿 drawLine 整数取整和像素半径
        return Rect.init(
            @as(i32, @intFromFloat(@floor(min_x))) - 1,
            @as(i32, @intFromFloat(@floor(min_y))) - 1,
            @as(i32, @intFromFloat(@ceil(max_x - min_x))) + 2,
            @as(i32, @intFromFloat(@ceil(max_y - min_y))) + 2,
        );
    }

    /// 投影网格并更新脏区域。每帧 render 前调用一次。
    pub fn update(self: *Renderer3D, mesh: *types.Mesh) void {
        self.projectMesh(mesh);
        self.updateDirty(mesh);
    }

    /// 读取 mesh.projected 计算脏区域。需先调用 projectMesh。
    fn updateDirty(self: *Renderer3D, mesh: *types.Mesh) void {
        const new_bb = self.computeBounds(mesh.projected);

        if (self.has_old_bb) {
            if (self.old_bb.x != new_bb.x or self.old_bb.y != new_bb.y or self.old_bb.w != new_bb.w or self.old_bb.h != new_bb.h) {
                self.node.invalidateArea(self.old_bb);
            }
        }

        self.node.invalidateArea(new_bb);
        self.old_bb = new_bb;
        self.has_old_bb = true;
    }

    /// 将 Canvas 的帧缓冲同步到 Renderer3D（在 drawCb 中自动调用）
    pub fn bindCanvas(self: *Renderer3D, canvas: *Canvas) void {
        self.area = canvas.area;
        self.buf = canvas.buf;
        self.clip = canvas.clip;
    }

    fn drawCb(node: *Node, canvas: *Canvas) void {
        // 通过 Node 地址反推 Renderer3D 指针（Node 是 Renderer3D 的第一个字段）
        const self: *Renderer3D = @ptrCast(@alignCast(node));
        self.bindCanvas(canvas);
        if (self.user_draw) |draw| {
            draw(self, canvas);
        }
    }

    pub fn project(self: *const Renderer3D, p: Point3D, screen_cx: f32, screen_cy: f32) TexVertex {
        const yaw_rad = self.yaw * (3.14159265 / 180.0);
        const pitch_rad = self.pitch * (3.14159265 / 180.0);
        const cos_y = @cos(yaw_rad);
        const sin_y = @sin(yaw_rad);
        const cos_p = @cos(pitch_rad);
        const sin_p = @sin(pitch_rad);

        const rx = p.x * cos_y + p.z * sin_y;
        const ry = p.y;
        const rz = -p.x * sin_y + p.z * cos_y;
        const ry2 = ry * cos_p + rz * sin_p;
        const rz2 = -ry * sin_p + rz * cos_p;

        const trans_z = rz2 + self.camera_dist;

        return .{
            .x = (rx * self.fov) / trans_z + screen_cx,
            .y = (ry2 * self.fov) / trans_z + screen_cy,
            .z = trans_z,
            .u = 0,
            .v = 0,
        };
    }

    pub fn projectAll(self: *const Renderer3D, vertices: []const Point3D, out: []TexVertex, screen_cx: f32, screen_cy: f32) void {
        for (vertices, 0..) |v, i| {
            out[i] = self.project(v, screen_cx, screen_cy);
        }
    }

    /// 投影网格并绘制边和面
    pub fn drawMesh(self: *Renderer3D, canvas: *Canvas, mesh: *types.Mesh, color: Color) void {
        self.projectMesh(mesh);
        self.updateDirty(mesh);
        self.drawProjected(canvas, mesh, color);
    }

    /// 绘制已投影的网格（边 + 纹理面）
    pub fn drawProjected(self: *Renderer3D, canvas: *Canvas, mesh: *const types.Mesh, color: Color) void {
        for (mesh.edges) |edge| {
            const v0 = mesh.projected[edge[0]];
            const v1 = mesh.projected[edge[1]];
            canvas.drawLine(@intFromFloat(v0.x), @intFromFloat(v0.y), @intFromFloat(v1.x), @intFromFloat(v1.y), color);
        }

        for (mesh.faces) |face| {
            const v0 = mesh.projected[face.verts[0]];
            const v1 = mesh.projected[face.verts[1]];
            const v2 = mesh.projected[face.verts[2]];
            if (face.tex) |tex| {
                self.drawTexTriangle(
                    .{ .x = v0.x, .y = v0.y, .z = v0.z, .u = face.uvs[0][0], .v = face.uvs[0][1] },
                    .{ .x = v1.x, .y = v1.y, .z = v1.z, .u = face.uvs[1][0], .v = face.uvs[1][1] },
                    .{ .x = v2.x, .y = v2.y, .z = v2.z, .u = face.uvs[2][0], .v = face.uvs[2][1] },
                    tex.pixels,
                    tex.w,
                    tex.h,
                    tex.stride,
                    tex.color_key,
                );
            }
        }
    }

    pub fn isFrontFace(_: *const Renderer3D, v0: TexVertex, v1: TexVertex, v2: TexVertex) bool {
        const dx1 = v1.x - v0.x;
        const dy1 = v1.y - v0.y;
        const dx2 = v2.x - v0.x;
        const dy2 = v2.y - v0.y;
        return (dx1 * dy2 - dx2 * dy1) < 0.0;
    }

    pub fn drawTexTriangle(
        self: *Renderer3D,
        v0: TexVertex,
        v1: TexVertex,
        v2: TexVertex,
        tex: []const u16,
        tw: i32,
        th: i32,
        stride: i32,
        color_key: u16,
    ) void {
        if (v0.z <= 0.0 or v1.z <= 0.0 or v2.z <= 0.0) return;

        var vt = [_]TexVertex{ v0, v1, v2 };
        if (vt[0].y > vt[1].y) std.mem.swap(TexVertex, &vt[0], &vt[1]);
        if (vt[0].y > vt[2].y) std.mem.swap(TexVertex, &vt[0], &vt[2]);
        if (vt[1].y > vt[2].y) std.mem.swap(TexVertex, &vt[1], &vt[2]);

        const y0: i32 = @intFromFloat(@ceil(vt[0].y));
        const y1: i32 = @intFromFloat(@ceil(vt[1].y));
        const y2: i32 = @intFromFloat(@ceil(vt[2].y));
        if (y0 >= y2) return;

        const clip_x_min = self.clip.x;
        const clip_x_max = self.clip.x + self.clip.w - 1;
        const clip_y_min = self.clip.y;
        const clip_y_max = self.clip.y + self.clip.h - 1;
        const buf_stride: usize = @intCast(self.area.w);

        const inv_z0 = 1.0 / vt[0].z;
        const inv_z1 = 1.0 / vt[1].z;
        const inv_z2 = 1.0 / vt[2].z;
        const uz0 = vt[0].u * inv_z0;
        const uz1 = vt[1].u * inv_z1;
        const uz2 = vt[2].u * inv_z2;
        const vz0 = vt[0].v * inv_z0;
        const vz1 = vt[1].v * inv_z1;
        const vz2 = vt[2].v * inv_z2;

        const dx10 = vt[1].x - vt[0].x;
        const dy10 = vt[1].y - vt[0].y;
        const dx20 = vt[2].x - vt[0].x;
        const dy20 = vt[2].y - vt[0].y;
        const cross = dx10 * dy20 - dx20 * dy10;
        if (@abs(cross) < 1e-6) return;
        const inv_cross = 1.0 / cross;

        const iz_dx = ((inv_z1 - inv_z0) * dy20 - (inv_z2 - inv_z0) * dy10) * inv_cross;
        const uz_dx = ((uz1 - uz0) * dy20 - (uz2 - uz0) * dy10) * inv_cross;
        const vz_dx = ((vz1 - vz0) * dy20 - (vz2 - vz0) * dy10) * inv_cross;

        const full_h = vt[2].y - vt[0].y;
        if (full_h < 1e-6) return;
        const inv_full_h = 1.0 / full_h;

        var y = y0;
        while (y < y2) : (y += 1) {
            if (y < clip_y_min or y > clip_y_max) continue;

            const y_center = @as(f32, @floatFromInt(y)) + 0.5;

            const t_le = (y_center - vt[0].y) * inv_full_h;
            const edge0_x = vt[0].x + (vt[2].x - vt[0].x) * t_le;
            const edge0_iz = inv_z0 + (inv_z2 - inv_z0) * t_le;
            const edge0_uz = uz0 + (uz2 - uz0) * t_le;
            const edge0_vz = vz0 + (vz2 - vz0) * t_le;

            var edge1_x: f32 = undefined;
            var edge1_iz: f32 = undefined;
            var edge1_uz: f32 = undefined;
            var edge1_vz: f32 = undefined;

            if (y < y1) {
                const top_h = vt[1].y - vt[0].y;
                if (top_h < 1e-6) continue;
                const t_se = (y_center - vt[0].y) / top_h;
                edge1_x = vt[0].x + (vt[1].x - vt[0].x) * t_se;
                edge1_iz = inv_z0 + (inv_z1 - inv_z0) * t_se;
                edge1_uz = uz0 + (uz1 - uz0) * t_se;
                edge1_vz = vz0 + (vz1 - vz0) * t_se;
            } else {
                const bot_h = vt[2].y - vt[1].y;
                if (bot_h < 1e-6) continue;
                const t_se = (y_center - vt[1].y) / bot_h;
                edge1_x = vt[1].x + (vt[2].x - vt[1].x) * t_se;
                edge1_iz = inv_z1 + (inv_z2 - inv_z1) * t_se;
                edge1_uz = uz1 + (uz2 - uz1) * t_se;
                edge1_vz = vz1 + (vz2 - vz1) * t_se;
            }

            var left_x = edge0_x;
            var left_iz = edge0_iz;
            var left_uz = edge0_uz;
            var left_vz = edge0_vz;
            var right_x = edge1_x;

            if (left_x > right_x) {
                std.mem.swap(f32, &left_x, &right_x);
                left_iz = edge1_iz;
                left_uz = edge1_uz;
                left_vz = edge1_vz;
            }

            const x_start: i32 = @intFromFloat(@ceil(left_x));
            const x_end: i32 = @intFromFloat(@ceil(right_x));

            if (x_start < x_end) {
                drawTexSpan(self, y, x_start, x_end, left_x, left_iz, left_uz, left_vz, iz_dx, uz_dx, vz_dx, tex, tw, th, stride, color_key, clip_x_min, clip_x_max, buf_stride);
            }
        }
    }

    fn drawTexSpan(
        self: *Renderer3D,
        y: i32,
        x_start: i32,
        x_end: i32,
        left_x: f32,
        s_iz: f32,
        s_uz: f32,
        s_vz: f32,
        iz_dx: f32,
        uz_dx: f32,
        vz_dx: f32,
        tex: []const u16,
        tw: i32,
        th: i32,
        stride: i32,
        color_key: u16,
        clip_x_min: i32,
        clip_x_max: i32,
        buf_stride: usize,
    ) void {
        if (y < self.clip.y or y > self.clip.y + self.clip.h - 1) return;
        if (x_start >= x_end) return;

        const x_correction = (@as(f32, @floatFromInt(x_start)) + 0.5) - left_x;
        var span_iz = s_iz + iz_dx * x_correction;
        var span_uz = s_uz + uz_dx * x_correction;
        var span_vz = s_vz + vz_dx * x_correction;

        var x = x_start;

        if (x < clip_x_min) {
            const skip = clip_x_min - x;
            span_iz += @as(f32, @floatFromInt(skip)) * iz_dx;
            span_uz += @as(f32, @floatFromInt(skip)) * uz_dx;
            span_vz += @as(f32, @floatFromInt(skip)) * vz_dx;
            x = clip_x_min;
        }
        var x_limit = x_end;
        if (x_limit > clip_x_max + 1) x_limit = clip_x_max + 1;

        const ly: usize = @intCast(y - self.area.y);
        const row_start = ly * buf_stride;

        while (x < x_limit) {
            const span_len = @min(16, x_limit - x);

            const cur_iz = span_iz;
            const cur_uz = span_uz;
            const cur_vz = span_vz;

            const end_iz = span_iz + @as(f32, @floatFromInt(span_len)) * iz_dx;
            const end_uz = span_uz + @as(f32, @floatFromInt(span_len)) * uz_dx;
            const end_vz = span_vz + @as(f32, @floatFromInt(span_len)) * vz_dx;

            if (@abs(cur_iz) < 1e-9 or @abs(end_iz) < 1e-9) {
                span_iz = end_iz;
                span_uz = end_uz;
                span_vz = end_vz;
                x += span_len;
                continue;
            }

            const start_u = cur_uz / cur_iz;
            const start_v = cur_vz / cur_iz;
            const end_u = end_uz / end_iz;
            const end_v = end_vz / end_iz;

            const inv_span_len = 1.0 / @as(f32, @floatFromInt(span_len));
            const u_step_f = (end_u - start_u) * inv_span_len;
            const v_step_f = (end_v - start_v) * inv_span_len;

            var u_fixed: i32 = @intFromFloat(start_u * 65536.0);
            var v_fixed: i32 = @intFromFloat(start_v * 65536.0);
            const u_step: i32 = @intFromFloat(u_step_f * 65536.0);
            const v_step: i32 = @intFromFloat(v_step_f * 65536.0);

            var remaining = span_len;
            var lx: usize = @intCast(x - self.area.x);
            while (remaining > 0) : (remaining -= 1) {
                const px_x = u_fixed >> 16;
                const px_y = v_fixed >> 16;

                if (px_x >= 0 and px_x < tw and px_y >= 0 and px_y < th) {
                    const sample = tex[@as(usize, @intCast(px_y)) * @as(usize, @intCast(stride)) + @as(usize, @intCast(px_x))];
                    if (sample != color_key) {
                        self.buf[row_start + lx] = sample;
                    }
                }

                u_fixed += u_step;
                v_fixed += v_step;
                lx += 1;
            }

            span_iz = end_iz;
            span_uz = end_uz;
            span_vz = end_vz;
            x += span_len;
        }
    }

    pub fn compositeText(_: *Renderer3D, buf: []u16, buf_stride: u32, x_off: u32, y_off: u32, str: []const u8, font_size: FontSize, color: Color) void {
        const m = font_size.metrics();
        const raw = color.toRgb565();
        var cx = x_off;
        for (str) |ch| {
            if (ch < 0x20 or ch > 0x7e) {
                cx += @intCast(m.w);
                continue;
            }
            var row: i32 = 0;
            while (row < m.h) : (row += 1) {
                var col: i32 = 0;
                while (col < m.w) : (col += 1) {
                    if (font.glyphLit(font_size, ch, col, row)) {
                        const px = @as(usize, @intCast(cx)) + @as(usize, @intCast(col));
                        const py = @as(usize, @intCast(y_off)) + @as(usize, @intCast(row));
                        buf[py * @as(usize, @intCast(buf_stride)) + px] = raw;
                    }
                }
            }
            cx += @intCast(m.w);
        }
    }
};
