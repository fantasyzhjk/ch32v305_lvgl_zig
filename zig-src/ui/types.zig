const std = @import("std");

pub const Align = enum {
    left,
    center,
    right,
};

pub const Point = struct {
    x: i32,
    y: i32,
};

pub const Point3D = struct {
    x: f32,
    y: f32,
    z: f32,
};

/// 4x4 矩阵，使用列向量约定：`result = matrix * point`。
pub const Mat4 = struct {
    data: [4][4]f32,

    pub fn identity() Mat4 {
        return .{ .data = .{
            .{ 1, 0, 0, 0 },
            .{ 0, 1, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ 0, 0, 0, 1 },
        } };
    }

    pub fn translation(value: Point3D) Mat4 {
        var result = identity();
        result.data[0][3] = value.x;
        result.data[1][3] = value.y;
        result.data[2][3] = value.z;
        return result;
    }

    pub fn scaling(value: Point3D) Mat4 {
        var result = identity();
        result.data[0][0] = value.x;
        result.data[1][1] = value.y;
        result.data[2][2] = value.z;
        return result;
    }

    pub fn rotationX(degrees: f32) Mat4 {
        const radians = degrees * (std.math.pi / 180.0);
        const c = @cos(radians);
        const s = @sin(radians);
        return .{ .data = .{
            .{ 1, 0, 0, 0 },
            .{ 0, c, -s, 0 },
            .{ 0, s, c, 0 },
            .{ 0, 0, 0, 1 },
        } };
    }

    pub fn rotationY(degrees: f32) Mat4 {
        const radians = degrees * (std.math.pi / 180.0);
        const c = @cos(radians);
        const s = @sin(radians);
        return .{ .data = .{
            .{ c, 0, s, 0 },
            .{ 0, 1, 0, 0 },
            .{ -s, 0, c, 0 },
            .{ 0, 0, 0, 1 },
        } };
    }

    pub fn rotationZ(degrees: f32) Mat4 {
        const radians = degrees * (std.math.pi / 180.0);
        const c = @cos(radians);
        const s = @sin(radians);
        return .{ .data = .{
            .{ c, -s, 0, 0 },
            .{ s, c, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ 0, 0, 0, 1 },
        } };
    }

    pub fn mul(a: Mat4, b: Mat4) Mat4 {
        var result: Mat4 = undefined;
        for (0..4) |row| {
            for (0..4) |column| {
                var value: f32 = 0;
                for (0..4) |k| {
                    value += a.data[row][k] * b.data[k][column];
                }
                result.data[row][column] = value;
            }
        }
        return result;
    }

    pub fn transformPoint(self: Mat4, point: Point3D) Point3D {
        const x = self.data[0][0] * point.x + self.data[0][1] * point.y + self.data[0][2] * point.z + self.data[0][3];
        const y = self.data[1][0] * point.x + self.data[1][1] * point.y + self.data[1][2] * point.z + self.data[1][3];
        const z = self.data[2][0] * point.x + self.data[2][1] * point.y + self.data[2][2] * point.z + self.data[2][3];
        const w = self.data[3][0] * point.x + self.data[3][1] * point.y + self.data[3][2] * point.z + self.data[3][3];

        if (@abs(w) > 1e-6 and @abs(w - 1.0) > 1e-6) {
            return .{ .x = x / w, .y = y / w, .z = z / w };
        }
        return .{ .x = x, .y = y, .z = z };
    }
};

/// 模型的局部坐标变换。组合顺序固定为 T * Rz * Ry * Rx * S。
pub const Transform3D = struct {
    position: Point3D = .{ .x = 0, .y = 0, .z = 0 },
    rotation_deg: Point3D = .{ .x = 0, .y = 0, .z = 0 },
    scale: Point3D = .{ .x = 1, .y = 1, .z = 1 },

    pub fn matrix(self: Transform3D) Mat4 {
        const scaled = Mat4.rotationX(self.rotation_deg.x).mul(Mat4.scaling(self.scale));
        const rotated_y = Mat4.rotationY(self.rotation_deg.y).mul(scaled);
        const rotated_z = Mat4.rotationZ(self.rotation_deg.z).mul(rotated_y);
        return Mat4.translation(self.position).mul(rotated_z);
    }

    pub fn inverseMatrix(self: Transform3D) ?Mat4 {
        if (@abs(self.scale.x) < 1e-6 or @abs(self.scale.y) < 1e-6 or @abs(self.scale.z) < 1e-6) return null;

        const inverse_translation = Mat4.translation(.{
            .x = -self.position.x,
            .y = -self.position.y,
            .z = -self.position.z,
        });
        const inverse_rz = Mat4.rotationZ(-self.rotation_deg.z).mul(inverse_translation);
        const inverse_ry = Mat4.rotationY(-self.rotation_deg.y).mul(inverse_rz);
        const inverse_rx = Mat4.rotationX(-self.rotation_deg.x).mul(inverse_ry);
        return Mat4.scaling(.{
            .x = 1.0 / self.scale.x,
            .y = 1.0 / self.scale.y,
            .z = 1.0 / self.scale.z,
        }).mul(inverse_rx);
    }

    pub fn localToWorld(self: Transform3D, point: Point3D) Point3D {
        return self.matrix().transformPoint(point);
    }

    pub fn worldToLocal(self: Transform3D, point: Point3D) ?Point3D {
        const inverse = self.inverseMatrix() orelse return null;
        return inverse.transformPoint(point);
    }
};

/// 屏幕空间顶点：屏幕坐标 (x, y) + 深度 z + 纹理坐标 (u, v)
pub const TexVertex = struct {
    x: f32,
    y: f32,
    z: f32,
    u: f32,
    v: f32,
};

pub const Rect = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,

    pub fn init(x: i32, y: i32, w: i32, h: i32) Rect {
        return .{ .x = x, .y = y, .w = w, .h = h };
    }

    pub fn isEmpty(self: Rect) bool {
        return self.w <= 0 or self.h <= 0;
    }

    pub fn area(self: Rect) i32 {
        if (self.isEmpty()) return 0;
        return self.w * self.h;
    }

    pub fn unionRect(a: Rect, b: Rect) Rect {
        if (a.isEmpty()) return b;
        if (b.isEmpty()) return a;

        const x1 = @min(a.x, b.x);
        const y1 = @min(a.y, b.y);
        const x2 = @max(a.x + a.w, b.x + b.w);
        const y2 = @max(a.y + a.h, b.y + b.h);
        return .{
            .x = x1,
            .y = y1,
            .w = x2 - x1,
            .h = y2 - y1,
        };
    }

    pub fn intersect(a: Rect, b: Rect) ?Rect {
        if (a.isEmpty() or b.isEmpty()) return null;

        const x1 = @max(a.x, b.x);
        const y1 = @max(a.y, b.y);
        const x2 = @min(a.x + a.w, b.x + b.w);
        const y2 = @min(a.y + a.h, b.y + b.h);

        if (x1 < x2 and y1 < y2) {
            return .{
                .x = x1,
                .y = y1,
                .w = x2 - x1,
                .h = y2 - y1,
            };
        }
        return null;
    }

    pub fn contains(self: Rect, x: i32, y: i32) bool {
        return x >= self.x and x < self.x + self.w and y >= self.y and y < self.y + self.h;
    }

    pub fn containsRect(self: Rect, other: Rect) bool {
        if (other.isEmpty()) return true;
        return other.x >= self.x and
            other.y >= self.y and
            other.x + other.w <= self.x + self.w and
            other.y + other.h <= self.y + self.h;
    }

    pub fn expanded(self: Rect, amount: i32) Rect {
        return .{
            .x = self.x - amount,
            .y = self.y - amount,
            .w = self.w + amount * 2,
            .h = self.h + amount * 2,
        };
    }
};

pub fn rect(x: i32, y: i32, w: i32, h: i32) Rect {
    return Rect.init(x, y, w, h);
}

pub const FontMetrics = struct {
    w: i32,
    h: i32,
};

pub const FontSize = enum {
    px12,
    px16,
    px24,

    pub fn metrics(self: FontSize) FontMetrics {
        return switch (self) {
            .px12 => .{ .w = 6, .h = 12 },
            .px16 => .{ .w = 8, .h = 16 },
            .px24 => .{ .w = 12, .h = 24 },
        };
    }
};

pub fn fontMetrics(size: FontSize) FontMetrics {
    return size.metrics();
}

pub fn textSize(size: FontSize, text: []const u8) FontMetrics {
    const metrics = fontMetrics(size);
    var line_w: i32 = 0;
    var max_w: i32 = 0;
    var lines: i32 = 1;

    for (text) |ch| {
        if (ch == '\n') {
            max_w = @max(max_w, line_w);
            line_w = 0;
            lines += 1;
        } else {
            line_w += metrics.w;
        }
    }

    max_w = @max(max_w, line_w);
    return .{ .w = max_w, .h = lines * metrics.h };
}

pub fn alignedX(area: Rect, content_w: i32, text_align: Align) i32 {
    return switch (text_align) {
        .left => area.x,
        .center => area.x + @max(0, @divTrunc(area.w - content_w, 2)),
        .right => area.x + @max(0, area.w - content_w),
    };
}

pub fn absI32(value: i32) i32 {
    return if (value < 0) -value else value;
}

/// 3D 纹理
pub const Texture = struct {
    pixels: []const u16,
    w: i32,
    h: i32,
    stride: i32,
    color_key: u16 = 0xFFFF,
};

/// 三角形面：3 个顶点索引 + 对应 UV + 可选纹理
pub const Face = struct {
    verts: [3]usize,
    uvs: [3][2]f32,
    tex: ?Texture = null,
};

/// 通用 3D 网格
pub const Mesh = struct {
    vertices: []const Point3D,
    edges: []const [2]usize,
    faces: []const Face = &.{},
};

fn expectPointApprox(expected: Point3D, actual: Point3D) !void {
    try std.testing.expectApproxEqAbs(expected.x, actual.x, 1e-4);
    try std.testing.expectApproxEqAbs(expected.y, actual.y, 1e-4);
    try std.testing.expectApproxEqAbs(expected.z, actual.z, 1e-4);
}

test "Transform3D applies scale rotation and translation in TRS order" {
    const transform = Transform3D{
        .position = .{ .x = 10, .y = 20, .z = 30 },
        .rotation_deg = .{ .x = 0, .y = 0, .z = 90 },
        .scale = .{ .x = 2, .y = 3, .z = 4 },
    };

    try expectPointApprox(
        .{ .x = 10, .y = 22, .z = 30 },
        transform.localToWorld(.{ .x = 1, .y = 0, .z = 0 }),
    );
}

test "Transform3D local and world conversion round trips" {
    const transform = Transform3D{
        .position = .{ .x = 4, .y = -7, .z = 12 },
        .rotation_deg = .{ .x = 17, .y = -31, .z = 48 },
        .scale = .{ .x = 2, .y = 0.5, .z = 3 },
    };
    const local = Point3D{ .x = 3, .y = -2, .z = 5 };
    const world = transform.localToWorld(local);
    try expectPointApprox(local, transform.worldToLocal(world).?);
}

test "Transform3D rejects a non-invertible scale" {
    const transform = Transform3D{ .scale = .{ .x = 1, .y = 0, .z = 1 } };
    try std.testing.expect(transform.inverseMatrix() == null);
    try std.testing.expect(transform.worldToLocal(.{ .x = 1, .y = 2, .z = 3 }) == null);
}
