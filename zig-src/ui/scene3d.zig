const std = @import("std");
const types = @import("types.zig");
const Color = @import("color.zig").Color565;

const Point3D = types.Point3D;
const Rect = types.Rect;
const TexVertex = types.TexVertex;

pub const Model3D = struct {
    mesh: *const types.Mesh,
    transform: types.Transform3D = .{},
    edge_color: Color = Color.WHITE,
    visible: bool = true,

    pub fn localToWorld(self: *const Model3D, point: Point3D) Point3D {
        return self.transform.localToWorld(point);
    }

    pub fn worldToLocal(self: *const Model3D, point: Point3D) ?Point3D {
        return self.transform.worldToLocal(point);
    }

    pub fn vertexToWorld(self: *const Model3D, vertex_index: usize) ?Point3D {
        if (vertex_index >= self.mesh.vertices.len) return null;
        return self.localToWorld(self.mesh.vertices[vertex_index]);
    }
};

pub const ProjectionRange = struct {
    start: usize,
    len: usize,

    pub fn end(self: ProjectionRange) usize {
        return self.start + self.len;
    }
};

const PreparedProjection3D = struct {
    fov: f32,
    camera_dist: f32,
    near_clip: f32,
    cos_y: f32,
    sin_y: f32,
    cos_p: f32,
    sin_p: f32,

    fn projectWorld(self: PreparedProjection3D, point: Point3D, screen_cx: f32, screen_cy: f32) TexVertex {
        const rx = point.x * self.cos_y + point.z * self.sin_y;
        const ry = point.y;
        const rz = -point.x * self.sin_y + point.z * self.cos_y;
        const ry2 = ry * self.cos_p + rz * self.sin_p;
        const rz2 = -ry * self.sin_p + rz * self.cos_p;
        const trans_z = rz2 + self.camera_dist;

        if (trans_z <= self.near_clip) {
            return .{ .x = screen_cx, .y = screen_cy, .z = trans_z, .u = 0, .v = 0 };
        }

        return .{
            .x = (rx * self.fov) / trans_z + screen_cx,
            .y = (ry2 * self.fov) / trans_z + screen_cy,
            .z = trans_z,
            .u = 0,
            .v = 0,
        };
    }
};

/// 保留 Renderer3D 原有相机语义的世界坐标投影参数。
pub const Projection3D = struct {
    fov: f32 = 60.0,
    camera_dist: f32 = 30.0,
    yaw: f32 = 0.0,
    pitch: f32 = 0.0,
    near_clip: f32 = 0.01,

    fn prepare(self: Projection3D) PreparedProjection3D {
        const yaw_rad = self.yaw * (std.math.pi / 180.0);
        const pitch_rad = self.pitch * (std.math.pi / 180.0);
        return .{
            .fov = self.fov,
            .camera_dist = self.camera_dist,
            .near_clip = self.near_clip,
            .cos_y = @cos(yaw_rad),
            .sin_y = @sin(yaw_rad),
            .cos_p = @cos(pitch_rad),
            .sin_p = @sin(pitch_rad),
        };
    }

    pub fn projectWorld(self: Projection3D, point: Point3D, screen_cx: f32, screen_cy: f32) TexVertex {
        return self.prepare().projectWorld(point, screen_cx, screen_cy);
    }

    pub fn projectAll(self: Projection3D, world_vertices: []const Point3D, out: []TexVertex, screen_cx: f32, screen_cy: f32) void {
        std.debug.assert(world_vertices.len == out.len);
        const prepared = self.prepare();
        for (world_vertices, 0..) |vertex, index| {
            out[index] = prepared.projectWorld(vertex, screen_cx, screen_cy);
        }
    }

    pub fn computeBounds(self: Projection3D, projected: []const TexVertex) ?Rect {
        var has_point = false;
        var min_x: f32 = 0;
        var max_x: f32 = 0;
        var min_y: f32 = 0;
        var max_y: f32 = 0;

        for (projected) |vertex| {
            if (vertex.z <= self.near_clip or !std.math.isFinite(vertex.x) or !std.math.isFinite(vertex.y)) continue;

            if (!has_point) {
                min_x = vertex.x;
                max_x = vertex.x;
                min_y = vertex.y;
                max_y = vertex.y;
                has_point = true;
                continue;
            }

            min_x = @min(min_x, vertex.x);
            max_x = @max(max_x, vertex.x);
            min_y = @min(min_y, vertex.y);
            max_y = @max(max_y, vertex.y);
        }

        if (!has_point) return null;
        return Rect.init(
            @as(i32, @intFromFloat(@floor(min_x))) - 1,
            @as(i32, @intFromFloat(@floor(min_y))) - 1,
            @as(i32, @intFromFloat(@ceil(max_x - min_x))) + 2,
            @as(i32, @intFromFloat(@ceil(max_y - min_y))) + 2,
        );
    }
};

/// 固定模型集合及其唯一的屏幕投影缓存。
pub const Scene3D = struct {
    allocator: std.mem.Allocator,
    models: []Model3D,
    projected: []TexVertex,
    ranges: []ProjectionRange,

    pub fn init(allocator: std.mem.Allocator, models: []Model3D) !Scene3D {
        const ranges = try allocator.alloc(ProjectionRange, models.len);
        errdefer allocator.free(ranges);

        var total_vertices: usize = 0;
        for (models, 0..) |model, index| {
            ranges[index] = .{ .start = total_vertices, .len = model.mesh.vertices.len };
            const sum = @addWithOverflow(total_vertices, model.mesh.vertices.len);
            if (sum[1] != 0) return error.VertexCountOverflow;
            total_vertices = sum[0];
        }

        const projected = try allocator.alloc(TexVertex, total_vertices);
        return .{
            .allocator = allocator,
            .models = models,
            .projected = projected,
            .ranges = ranges,
        };
    }

    pub fn deinit(self: *Scene3D) void {
        self.allocator.free(self.projected);
        self.allocator.free(self.ranges);
        self.projected = &.{};
        self.ranges = &.{};
        self.models = &.{};
    }

    pub fn projectionRange(self: *const Scene3D, model_index: usize) ?ProjectionRange {
        if (model_index >= self.ranges.len) return null;
        return self.ranges[model_index];
    }

    pub fn projectedFor(self: *Scene3D, model_index: usize) ?[]TexVertex {
        const range = self.projectionRange(model_index) orelse return null;
        return self.projected[range.start..range.end()];
    }

    pub fn projectedForConst(self: *const Scene3D, model_index: usize) ?[]const TexVertex {
        const range = self.projectionRange(model_index) orelse return null;
        return self.projected[range.start..range.end()];
    }

    /// 将所有可见模型直接投影到共享缓存，不保留世界顶点副本。
    pub fn projectAll(self: *Scene3D, projection: Projection3D, screen_cx: f32, screen_cy: f32) ?Rect {
        var scene_bounds: ?Rect = null;
        const prepared_projection = projection.prepare();

        for (self.models, 0..) |*model, model_index| {
            if (!model.visible) continue;

            const out = self.projectedFor(model_index).?;
            const world_matrix = model.transform.matrix();
            for (model.mesh.vertices, 0..) |vertex, vertex_index| {
                const world_vertex = world_matrix.transformPoint(vertex);
                out[vertex_index] = prepared_projection.projectWorld(world_vertex, screen_cx, screen_cy);
            }

            if (projection.computeBounds(out)) |model_bounds| {
                scene_bounds = if (scene_bounds) |bounds| Rect.unionRect(bounds, model_bounds) else model_bounds;
            }
        }

        return scene_bounds;
    }
};

fn expectPointApprox(expected: Point3D, actual: Point3D) !void {
    try std.testing.expectApproxEqAbs(expected.x, actual.x, 1e-4);
    try std.testing.expectApproxEqAbs(expected.y, actual.y, 1e-4);
    try std.testing.expectApproxEqAbs(expected.z, actual.z, 1e-4);
}

test "Scene3D assigns two model instances contiguous shared cache ranges" {
    const vertices = [_]Point3D{
        .{ .x = -1, .y = 0, .z = 0 },
        .{ .x = 1, .y = 0, .z = 0 },
    };
    const mesh = types.Mesh{ .vertices = &vertices, .edges = &.{} };
    var models = [_]Model3D{
        .{ .mesh = &mesh },
        .{ .mesh = &mesh, .transform = .{ .position = .{ .x = 10, .y = 0, .z = 0 } } },
    };

    var scene = try Scene3D.init(std.testing.allocator, &models);
    defer scene.deinit();

    try std.testing.expectEqual(@as(usize, 4), scene.projected.len);
    try std.testing.expectEqual(ProjectionRange{ .start = 0, .len = 2 }, scene.projectionRange(0).?);
    try std.testing.expectEqual(ProjectionRange{ .start = 2, .len = 2 }, scene.projectionRange(1).?);
    try expectPointApprox(.{ .x = 9, .y = 0, .z = 0 }, models[1].vertexToWorld(0).?);

    _ = scene.projectAll(.{}, 100, 100);
    try std.testing.expect(scene.projectedFor(0).?.ptr != scene.projectedFor(1).?.ptr);
}

test "Scene3D handles empty meshes and empty scenes" {
    const empty_mesh = types.Mesh{ .vertices = &.{}, .edges = &.{} };
    var models = [_]Model3D{.{ .mesh = &empty_mesh }};
    var scene = try Scene3D.init(std.testing.allocator, &models);
    defer scene.deinit();

    try std.testing.expectEqual(@as(usize, 0), scene.projected.len);
    try std.testing.expect(scene.projectAll(.{}, 0, 0) == null);

    var no_models: [0]Model3D = .{};
    var empty_scene = try Scene3D.init(std.testing.allocator, &no_models);
    defer empty_scene.deinit();
    try std.testing.expect(empty_scene.projectAll(.{}, 0, 0) == null);
}

test "Scene3D excludes hidden and camera-behind models from bounds" {
    const vertices = [_]Point3D{.{ .x = 1, .y = 2, .z = 0 }};
    const mesh = types.Mesh{ .vertices = &vertices, .edges = &.{} };
    var models = [_]Model3D{
        .{ .mesh = &mesh, .visible = false },
        .{ .mesh = &mesh, .transform = .{ .position = .{ .x = 0, .y = 0, .z = -40 } } },
    };
    var scene = try Scene3D.init(std.testing.allocator, &models);
    defer scene.deinit();

    try std.testing.expect(scene.projectAll(.{ .camera_dist = 30 }, 50, 50) == null);
}
