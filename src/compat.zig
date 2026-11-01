//! Shims for the Zig 0.16 and 0.17 APIs. Private to the module.

const std = @import("std");
const mem = std.mem;

/// Zig 0.17's `zig fmt` rewrites `@intFromEnum` to `@backingInt` and
/// `@enumFromInt` to `@fromBackingInt`, which Zig 0.16 cannot compile. Keep
/// the builtins out of the formatter's reach until 0.16 support drops.
// zig fmt: off
pub fn enumToInt(e: anytype) @typeInfo(@TypeOf(e)).@"enum".tag_type {
    return @intFromEnum(e);
}
pub fn enumFromInt(comptime E: type, raw: anytype) E {
    return @enumFromInt(raw);
}
// zig fmt: on

// Zig 0.17 split a container's `fields` into parallel `field_names` and
// `field_types` arrays. These accessors keep one loop shape for both.
pub fn fieldCount(comptime info: anytype) usize {
    if (comptime @hasField(@TypeOf(info), "field_names")) return info.field_names.len;
    return info.fields.len;
}

pub fn fieldName(comptime info: anytype, comptime i: usize) [:0]const u8 {
    if (comptime @hasField(@TypeOf(info), "field_names")) return info.field_names[i];
    return info.fields[i].name;
}

pub fn fieldType(comptime info: anytype, comptime i: usize) type {
    if (comptime @hasField(@TypeOf(info), "field_names")) return info.field_types[i];
    return info.fields[i].type;
}

pub fn enumIsExhaustive(comptime info: anytype) bool {
    if (comptime @hasField(@TypeOf(info), "mode")) return info.mode == .exhaustive;
    return info.is_exhaustive;
}

/// Zig 0.17 removed the `**` array-repeat operator.
pub fn repeatString(comptime s: []const u8, comptime n: usize) [s.len * n]u8 {
    var out: [s.len * n]u8 = undefined;
    for (0..n) |i| @memcpy(out[i * s.len ..][0..s.len], s);
    return out;
}

// `std.fmt.allocPrint`/`bufPrint` are the only spelling that compiles on
// 0.16; 0.17 moved them to `Allocator.print` and `mem.print`. Lint runs
// against the 0.16 std (`ziglint-0-16`), so the fallback is not deprecated.
// ziglint-ignore: Z023 -- mirrors the std.fmt argument order
pub fn allocPrint(a: mem.Allocator, comptime format: []const u8, args: anytype) ![]u8 {
    if (comptime @hasDecl(mem.Allocator, "print")) return a.print(format, args);
    return std.fmt.allocPrint(a, format, args);
}

// ziglint-ignore: Z023 -- mirrors the std.fmt argument order
pub fn bufPrint(buf: []u8, comptime format: []const u8, args: anytype) ![]u8 {
    if (comptime @hasDecl(mem, "print")) return mem.print(buf, format, args);
    return std.fmt.bufPrint(buf, format, args);
}
