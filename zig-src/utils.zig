const ui = @import("ui/ui.zig");
const ch32 = @import("ch32.zig");
const hal = ch32.hal;

const Point3D = ui.Point3D;
const Color = ui.Color565;

pub const Edge = [2]usize;

/// 生成正方体顶点
pub fn createCubeVertices(comptime size: f32) [8]Point3D {
    const half = size / 2.0;
    return [8]Point3D{
        .{ .x = -half, .y = -half, .z = -half },
        .{ .x = half, .y = -half, .z = -half },
        .{ .x = half, .y = half, .z = -half },
        .{ .x = -half, .y = half, .z = -half },
        .{ .x = -half, .y = -half, .z = half },
        .{ .x = half, .y = -half, .z = half },
        .{ .x = half, .y = half, .z = half },
        .{ .x = -half, .y = half, .z = half },
    };
}

/// 根据顶点距离自动生成边（comptime）
pub fn autoGenEdges(comptime vertices: []const Point3D, comptime max_dist: f32) []const Edge {
    comptime var edge_count: usize = 0;
    inline for (vertices, 0..) |v1, i| {
        inline for (vertices[i + 1 ..], 0..) |v2, j| {
            _ = j;
            const dx = v1.x - v2.x;
            const dy = v1.y - v2.y;
            const dz = v1.z - v2.z;
            const dist = @sqrt(dx * dx + dy * dy + dz * dz);
            if (dist > 0.1 and dist <= max_dist) {
                edge_count += 1;
            }
        }
    }

    comptime var edges: [edge_count]Edge = undefined;
    comptime var idx: usize = 0;

    inline for (vertices, 0..) |v1, i| {
        inline for (vertices[i + 1 ..], 0..) |v2, j| {
            const real_j = j + i + 1;
            const dx = v1.x - v2.x;
            const dy = v1.y - v2.y;
            const dz = v1.z - v2.z;
            const dist = @sqrt(dx * dx + dy * dy + dz * dz);
            if (dist > 0.1 and dist <= max_dist) {
                edges[idx] = .{ i, real_j };
                idx += 1;
            }
        }
    }

    const final_edges = edges;
    return &final_edges;
}

/// 硬件随机数范围 [min, max]
pub fn hwRandRange(min: i32, max: i32) i32 {
    const r = hal.RNG_GetRandomNumber();
    return min + @as(i32, @intCast(r % @as(u32, @intCast(max - min + 1))));
}

/// RGB565 颜色线性插值
pub fn lerpColor(a: Color, b: Color, t: f32) Color {
    const a565: u16 = a.toRgb565();
    const b565: u16 = b.toRgb565();
    const ar: f32 = @floatFromInt((a565 >> 11) & 0x1F);
    const ag: f32 = @floatFromInt((a565 >> 5) & 0x3F);
    const ab: f32 = @floatFromInt(a565 & 0x1F);
    const br: f32 = @floatFromInt((b565 >> 11) & 0x1F);
    const bg: f32 = @floatFromInt((b565 >> 5) & 0x3F);
    const bb: f32 = @floatFromInt(b565 & 0x1F);
    const r: u16 = @intFromFloat(lerp(ar, br, t));
    const g: u16 = @intFromFloat(lerp(ag, bg, t));
    const bl: u16 = @intFromFloat(lerp(ab, bb, t));
    return .{ .data = (r << 11) | (g << 5) | bl };
}

/// 浮点线性插值
pub fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}
