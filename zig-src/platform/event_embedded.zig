/// Embedded event source: USB serial → RotationEvent
const usb = @import("../usb.zig");
const Event = @import("../event.zig").Event;
const Rotation = @import("../event.zig").Rotation;

var cmd_buf: [64]u8 = undefined;
var cmd_len: u32 = 0;

pub fn poll() Event {
    const data = usb.task();
    for (data) |b| {
        if (b == '\n' or b == '\r') {
            if (cmd_len > 0) {
                const ev = parseRotation(cmd_buf[0..cmd_len]);
                cmd_len = 0;
                if (ev) |r| return .{ .rotation = r };
            }
        } else if (cmd_len < cmd_buf.len) {
            cmd_buf[cmd_len] = b;
            cmd_len += 1;
        }
    }
    return .none;
}

fn parseFloat(buf: []const u8) ?struct { value: f32, consumed: u32 } {
    var i: usize = 0;
    var negative = false;
    if (i < buf.len and (buf[i] == '-' or buf[i] == '+')) {
        negative = buf[i] == '-';
        i += 1;
    }
    var int_part: f32 = 0;
    while (i < buf.len and buf[i] >= '0' and buf[i] <= '9') {
        int_part = int_part * 10.0 + @as(f32, @floatFromInt(buf[i] - '0'));
        i += 1;
    }
    var frac_part: f32 = 0;
    var frac_div: f32 = 1.0;
    if (i < buf.len and buf[i] == '.') {
        i += 1;
        while (i < buf.len and buf[i] >= '0' and buf[i] <= '9') {
            frac_part = frac_part * 10.0 + @as(f32, @floatFromInt(buf[i] - '0'));
            frac_div *= 10.0;
            i += 1;
        }
    }
    if (i == 0) return null;
    var v = int_part + frac_part / frac_div;
    if (negative) v = -v;
    return .{ .value = v, .consumed = @intCast(i) };
}

fn parseRotation(line: []const u8) ?Rotation {
    var pos: usize = 0;
    while (pos < line.len and line[pos] == ' ') pos += 1;
    var yaw: f32 = 0;
    var pitch: f32 = 0;
    while (pos < line.len) {
        if (line[pos] == 'Y' or line[pos] == 'y') {
            pos += 1;
            if (parseFloat(line[pos..])) |r| {
                yaw = r.value;
                pos += r.consumed;
            }
        } else if (line[pos] == 'P' or line[pos] == 'p') {
            pos += 1;
            if (parseFloat(line[pos..])) |r| {
                pitch = r.value;
                pos += r.consumed;
            }
        } else if (line[pos] == ',') {
            pos += 1;
        } else {
            break;
        }
    }
    return .{ .yaw = yaw, .pitch = pitch };
}
