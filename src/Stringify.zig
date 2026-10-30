//! Writes a `std.json.Value` as strict JSON.
//!
//! The output is JSON, not JSON5. A non-finite float is the one value JSON
//! cannot spell, so it is written as `NaN`, `Infinity`, or `-Infinity`: the
//! JSON5 form, and the only form that reads back. A non-finite float is
//! `error.NonFiniteFloat` when `allow_nonfinite` is false.

const std = @import("std");
const Io = std.Io;
const Writer = Io.Writer;
const mem = std.mem;

const Value = std.json.Value;

const Stringify = @This();

/// What writing can fail with: the sink, a non-finite float the options
/// reject, or a tree nested deeper than the writer walks.
pub const Error = Writer.Error || error{ NonFiniteFloat, NestingTooDeep };

/// How to write a value.
pub const Options = struct {
    /// The whitespace between tokens. The default is one line with no spaces.
    whitespace: enum {
        minified,
        indent_1,
        indent_2,
        indent_3,
        indent_4,
        indent_8,
        indent_tab,
    } = .minified,
    /// Escape every non-ASCII character as `\uXXXX`, which keeps the output
    /// inside ASCII.
    escape_unicode: bool = false,
    /// false makes `NaN` and `Infinity` fail instead of being written.
    allow_nonfinite: bool = true,
};

/// How deep a tree may nest. A deeper tree is `error.NestingTooDeep`, so the
/// writer cannot overflow the stack on a tree a caller built by hand.
const max_depth = 256;

/// Write `value` to `writer`.
pub fn value(root: Value, options: Options, writer: *Writer) Error!void {
    try writeValue(root, options, writer, 0);
}

fn writeValue(item: Value, options: Options, writer: *Writer, depth: u32) Error!void {
    if (depth > max_depth) return error.NestingTooDeep;
    switch (item) {
        .null => try writer.writeAll("null"),
        .bool => |flag| try writer.writeAll(if (flag) "true" else "false"),
        .integer => |number| try writer.print("{d}", .{number}),
        .float => |number| try writeFloat(number, options, writer),
        .number_string => |text| try writer.writeAll(text),
        .string => |text| try writeString(text, options, writer),
        .array => |array| try writeArray(array.items, options, writer, depth),
        .object => |object| try writeObject(object, options, writer, depth),
    }
}

fn writeArray(items: []const Value, options: Options, writer: *Writer, depth: u32) Error!void {
    if (items.len == 0) {
        try writer.writeAll("[]");
        return;
    }
    try writer.writeByte('[');
    for (items, 0..) |item, i| {
        if (i != 0) try writer.writeByte(',');
        try indent(options, writer, depth + 1);
        try writeValue(item, options, writer, depth + 1);
    }
    try indent(options, writer, depth);
    try writer.writeByte(']');
}

fn writeObject(object: std.json.ObjectMap, options: Options, writer: *Writer, depth: u32) Error!void {
    if (object.count() == 0) {
        try writer.writeAll("{}");
        return;
    }
    try writer.writeByte('{');
    var it = object.iterator();
    var i: usize = 0;
    while (it.next()) |entry| : (i += 1) {
        if (i != 0) try writer.writeByte(',');
        try indent(options, writer, depth + 1);
        try writeString(entry.key_ptr.*, options, writer);
        try writer.writeByte(':');
        if (options.whitespace != .minified) try writer.writeByte(' ');
        try writeValue(entry.value_ptr.*, options, writer, depth + 1);
    }
    try indent(options, writer, depth);
    try writer.writeByte('}');
}

fn writeString(text: []const u8, options: Options, writer: *Writer) Error!void {
    try std.json.Stringify.encodeJsonString(text, .{ .escape_unicode = options.escape_unicode }, writer);
}

fn writeFloat(number: f64, options: Options, writer: *Writer) Error!void {
    if (std.math.isNan(number)) {
        if (!options.allow_nonfinite) return error.NonFiniteFloat;
        return writer.writeAll("NaN");
    }
    if (std.math.isInf(number)) {
        if (!options.allow_nonfinite) return error.NonFiniteFloat;
        return writer.writeAll(if (number < 0) "-Infinity" else "Infinity");
    }
    var buffer: [std.fmt.float.bufferSize(.decimal, f64)]u8 = undefined;
    const text = std.fmt.float.render(&buffer, number, .{ .mode = .decimal }) catch unreachable;
    try writer.writeAll(text);
    // `10` and `10.0` are the same number, but only the second reads back as a
    // float. Keep the tree's tag across a write and a parse.
    if (mem.findScalar(u8, text, '.') == null) try writer.writeAll(".0");
}

fn indent(options: Options, writer: *Writer, level: u32) Writer.Error!void {
    const character: u8 = switch (options.whitespace) {
        .minified => return,
        .indent_tab => '\t',
        else => ' ',
    };
    const width: u32 = switch (options.whitespace) {
        .minified => unreachable,
        .indent_1 => 1,
        .indent_2 => 2,
        .indent_3 => 3,
        .indent_4 => 4,
        .indent_8 => 8,
        .indent_tab => 1,
    };
    try writer.writeByte('\n');
    try writer.splatByteAll(character, @as(usize, level) * @as(usize, width));
}
