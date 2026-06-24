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

    /// 模型局部坐标到 Scene3D 根坐标；最终世界坐标应使用 Scene3D.modelToWorld。
    pub fn localToScene(self: *const Model3D, point: Point3D) Point3D {
        return self.transform.localToWorld(point);
    }

    pub fn sceneToLocal(self: *const Model3D, point: Point3D) ?Point3D {
        return self.transform.worldToLocal(point);
    }

    pub fn vertexToScene(self: *const Model3D, vertex_index: usize) ?Point3D {
        if (vertex_index >= self.mesh.vertices.len) return null;
        return self.localToScene(self.mesh.vertices[vertex_index]);
    }
};

pub const ProjectionRange = struct {
    start: usize,
    len: usize,

    pub fn end(self: ProjectionRange) usize {
        return self.start + self.len;
    }
};

const PreparedCamera3D = struct {
    fov: f32,
    near_clip: f32,
    view_matrix: types.Mat4,

    fn projectWorld(self: PreparedCamera3D, point: Point3D, screen_cx: f32, screen_cy: f32) TexVertex {
        const view = self.view_matrix.transformPoint(point);

        if (view.z <= self.near_clip) {
            return .{ .x = screen_cx, .y = screen_cy, .z = view.z, .u = 0, .v = 0 };
        }

        return .{
            .x = (view.x * self.fov) / view.z + screen_cx,
            .y = (view.y * self.fov) / view.z + screen_cy,
            .z = view.z,
            .u = 0,
            .v = 0,
        };
    }
};

/// 位于世界坐标中的相机。默认位于 z=-30，朝世界 +Z 方向观察。
pub const Camera3D = struct {
    position: Point3D = .{ .x = 0, .y = 0, .z = -30 },
    /// 绕世界 Y 轴的相机航向角，单位为度。
    yaw: f32 = 0.0,
    /// 绕相机 X 轴的仰角，单位为度；在当前 Y 向下坐标系中正值表示抬头。
    pitch: f32 = 0.0,
    fov: f32 = 60.0,
    near_clip: f32 = 0.01,

    /// 世界坐标到相机视图坐标：Rx(-pitch) * Ry(-yaw) * T(-position)。
    pub fn viewMatrix(self: Camera3D) types.Mat4 {
        const inverse_translation = types.Mat4.translation(.{
            .x = -self.position.x,
            .y = -self.position.y,
            .z = -self.position.z,
        });
        const inverse_yaw = types.Mat4.rotationY(-self.yaw).mul(inverse_translation);
        return types.Mat4.rotationX(-self.pitch).mul(inverse_yaw);
    }

    pub fn worldMatrix(self: Camera3D) types.Mat4 {
        const pitched = types.Mat4.rotationY(self.yaw).mul(types.Mat4.rotationX(self.pitch));
        return types.Mat4.translation(self.position).mul(pitched);
    }

    pub fn worldToView(self: Camera3D, point: Point3D) Point3D {
        return self.viewMatrix().transformPoint(point);
    }

    pub fn viewToWorld(self: Camera3D, point: Point3D) Point3D {
        return self.worldMatrix().transformPoint(point);
    }

    fn prepare(self: Camera3D) PreparedCamera3D {
        return .{
            .fov = self.fov,
            .near_clip = self.near_clip,
            .view_matrix = self.viewMatrix(),
        };
    }

    pub fn projectWorld(self: Camera3D, point: Point3D, screen_cx: f32, screen_cy: f32) TexVertex {
        return self.prepare().projectWorld(point, screen_cx, screen_cy);
    }

    pub fn projectAll(self: Camera3D, world_vertices: []const Point3D, out: []TexVertex, screen_cx: f32, screen_cy: f32) void {
        std.debug.assert(world_vertices.len == out.len);
        const prepared = self.prepare();
        for (world_vertices, 0..) |vertex, index| {
            out[index] = prepared.projectWorld(vertex, screen_cx, screen_cy);
        }
    }

    pub fn computeBounds(self: Camera3D, projected: []const TexVertex) ?Rect {
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
    /// 作用于所有模型的世界根变换，与相机变换相互独立。
    world_transform: types.Transform3D = .{},
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
            .world_transform = .{},
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

    pub fn modelToWorld(self: *const Scene3D, model_index: usize, point: Point3D) ?Point3D {
        if (model_index >= self.models.len) return null;
        const model_point = self.models[model_index].localToScene(point);
        return self.world_transform.localToWorld(model_point);
    }

    pub fn worldToModel(self: *const Scene3D, model_index: usize, point: Point3D) ?Point3D {
        if (model_index >= self.models.len) return null;
        const scene_point = self.world_transform.worldToLocal(point) orelse return null;
        return self.models[model_index].sceneToLocal(scene_point);
    }

    pub fn vertexToWorld(self: *const Scene3D, model_index: usize, vertex_index: usize) ?Point3D {
        if (model_index >= self.models.len) return null;
        const model = &self.models[model_index];
        if (vertex_index >= model.mesh.vertices.len) return null;
        return self.modelToWorld(model_index, model.mesh.vertices[vertex_index]);
    }

    /// 将所有可见模型直接投影到共享缓存，不保留世界顶点副本。
    pub fn projectAll(self: *Scene3D, camera: Camera3D, screen_cx: f32, screen_cy: f32) ?Rect {
        var scene_bounds: ?Rect = null;
        const prepared_camera = camera.prepare();
        const world_matrix = self.world_transform.matrix();

        for (self.models, 0..) |*model, model_index| {
            if (!model.visible) continue;

            const out = self.projectedFor(model_index).?;
            const model_to_world = world_matrix.mul(model.transform.matrix());
            for (model.mesh.vertices, 0..) |vertex, vertex_index| {
                const world_vertex = model_to_world.transformPoint(vertex);
                out[vertex_index] = prepared_camera.projectWorld(world_vertex, screen_cx, screen_cy);
            }

            if (camera.computeBounds(out)) |model_bounds| {
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
    try expectPointApprox(.{ .x = 9, .y = 0, .z = 0 }, scene.vertexToWorld(1, 0).?);

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

    try std.testing.expect(scene.projectAll(.{}, 50, 50) == null);
}

test "Camera3D position yaw and pitch operate in world coordinates" {
    const translated = Camera3D{ .position = .{ .x = 10, .y = 0, .z = -30 } };
    const translated_view = translated.worldToView(.{ .x = 10, .y = 0, .z = 0 });
    try expectPointApprox(.{ .x = 0, .y = 0, .z = 30 }, translated_view);

    const yawed = Camera3D{ .position = .{ .x = 0, .y = 0, .z = 0 }, .yaw = 90 };
    try expectPointApprox(.{ .x = 0, .y = 0, .z = 10 }, yawed.worldToView(.{ .x = 10, .y = 0, .z = 0 }));

    const pitched = Camera3D{ .position = .{ .x = 0, .y = 0, .z = 0 }, .pitch = 90 };
    try expectPointApprox(.{ .x = 0, .y = 0, .z = 10 }, pitched.worldToView(.{ .x = 0, .y = -10, .z = 0 }));

    const oriented = Camera3D{
        .position = .{ .x = 4, .y = -3, .z = -12 },
        .yaw = 32,
        .pitch = -18,
    };
    const point = Point3D{ .x = 7, .y = -3, .z = 18 };
    try expectPointApprox(point, oriented.viewToWorld(oriented.worldToView(point)));
}

test "Scene3D world transform is independent from model transforms" {
    const vertices = [_]Point3D{.{ .x = 1, .y = 0, .z = 0 }};
    const mesh = types.Mesh{ .vertices = &vertices, .edges = &.{} };
    var models = [_]Model3D{.{
        .mesh = &mesh,
        .transform = .{ .position = .{ .x = 1, .y = 0, .z = 0 } },
    }};
    var scene = try Scene3D.init(std.testing.allocator, &models);
    defer scene.deinit();
    scene.world_transform = .{
        .position = .{ .x = 10, .y = 0, .z = 0 },
        .rotation_deg = .{ .x = 0, .y = 0, .z = 90 },
    };

    const world = scene.vertexToWorld(0, 0).?;
    try expectPointApprox(.{ .x = 10, .y = 2, .z = 0 }, world);
    try expectPointApprox(vertices[0], scene.worldToModel(0, world).?);
}
