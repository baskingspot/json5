//! JSON5 in Zig: unquoted keys, single quotes, hex numbers, NaN, and comments.
//!
//! `parseFromSlice` reads one JSON5 value into a `std.json.Value` tree, built
//! from the same `Value`, `ObjectMap`, and `Array` types as `std.json`, so a
//! tree moves between the two parsers. Given a destination type, it decodes
//! that tree through `std.json.parseFromValue`. `Stringify` writes either form
//! as strict JSON.
//!
//! Name characters are an approximation: ASCII IdentifierStart and
//! IdentifierPart, plus any non-ASCII code point. The exact ES5.1 categories
//! would need a Unicode property table this package does not vendor.
//!
//! A `\uXXXX` escape or a surrogate pair decodes before the check, so
//! `\uD801\uDC00` and U+10400 are the same name character. A lone surrogate
//! is an error.
//!
//! A number is `.integer` when its literal has no fraction and no exponent,
//! fits `i64`, and is not a negative zero. Every other number is `.float`,
//! including a hexadecimal value past `i64`. `.number_string` is never
//! produced.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Io = std.Io;
/// A JSON5 value. It is `std.json.Value`, so the tags, the object map, and
/// the array are the ones in `std.json`.
pub const Value = std.json.Value;
/// An array of values, the `std.json` one.
pub const Array = std.json.Array;
/// An object's member map, the `std.json` one. Member order is insertion
/// order, and a repeated name keeps its first position.
pub const ObjectMap = std.json.ObjectMap;

/// Where a parse failed: the bytes, the position, and a message. The caller
/// owns this struct and passes it in `ParseOptions`.
pub const Diagnostics = @import("Diagnostics.zig");
/// Byte offsets into the source: the first offending byte and one past the last.
pub const Span = Diagnostics.Span;
const Parser = @import("Parser.zig");
/// Writes a `std.json.Value` as strict JSON. See `Stringify.Options`.
pub const Stringify = @import("Stringify.zig");

/// What a parse can return: the source breaks the grammar, the allocator
/// failed, or the typed pass rejected the tree. On `error.SyntaxError`,
/// `options.diagnostics` says where.
pub const ParseError = Allocator.Error || std.json.ParseFromValueError || error{SyntaxError};

/// How to parse a document.
pub const ParseOptions = struct {
    /// Filled on `error.SyntaxError`. Untouched when the parse succeeds, and
    /// on `error.OutOfMemory`. Null means the caller wants only the error.
    diagnostics: ?*Diagnostics,
    /// The `std.json` options, used when `T` is not `std.json.Value`:
    /// duplicate fields, unknown fields, string allocation, and numbers.
    json: std.json.ParseOptions,

    /// No diagnostics, and `std.json`'s defaults for the typed pass.
    pub const init: ParseOptions = .{ .diagnostics = null, .json = .{} };
};

/// A parsed value and the memory that holds it.
pub fn Parsed(comptime T: type) type {
    return struct {
        const Self = @This();

        /// The arena that owns every string, object, and array in `value`.
        ///
        /// It is heap-allocated on purpose. `std.json.Array` is a managed list
        /// that carries the allocator it was built with, and that allocator's
        /// pointer is this arena. A value field would move with `Parsed`, and
        /// every array in the tree would point at a dead stack slot.
        arena: *ArenaAllocator,
        /// The root value.
        value: T,

        /// Free the arena and everything the value points at. Takes self by
        /// value, like `std.json.Parsed`.
        pub fn deinit(self: Self) void {
            const allocator = self.arena.child_allocator;
            self.arena.deinit();
            allocator.destroy(self.arena);
        }
    };
}

/// Parse one JSON5 document into `T`.
///
/// `T` is any type `std.json.parseFromValue` accepts: a struct, a union, an
/// enum, a slice, or `std.json.Value` for the tree. Every string, object, and
/// array the value points at is copied into an arena that the returned
/// `Parsed` owns, so the source may be freed as soon as this returns.
///
/// When `T` is `std.json.Value`, the tree comes back as it was parsed. For
/// anything else, the parser builds the tree first and `std.json` turns it
/// into `T` with `options.json`. A document that breaks the grammar is
/// `error.SyntaxError`, and `options.diagnostics` says where.
pub fn parseFromSlice(
    comptime T: type,
    allocator: Allocator,
    source: []const u8,
    options: ParseOptions,
) ParseError!Parsed(T) {
    const arena = try allocator.create(ArenaAllocator);
    errdefer allocator.destroy(arena);
    arena.* = .init(allocator);
    errdefer arena.deinit();

    const value = try parseFromSliceLeaky(T, arena.allocator(), source, options);
    return .{ .arena = arena, .value = value };
}

/// Parse one JSON5 document into `T`, in memory the caller already owns.
///
/// Use this when the caller has an arena whose lifetime is known, such as a
/// request or a configuration load. The returned value owns nothing, and
/// freeing it is the caller's problem. The source is still copied, so it may
/// be freed as soon as this returns. The arena must stay at the same address
/// while the value lives, because a `std.json.Value` tree's arrays hold the
/// allocator built from it.
pub fn parseFromSliceLeaky(
    comptime T: type,
    allocator: Allocator,
    source: []const u8,
    options: ParseOptions,
) ParseError!T {
    const value = try parseTree(allocator, source, options);
    if (T == Value) return value;
    return std.json.parseFromValueLeaky(T, allocator, value, options.json);
}

/// The tree-only pass, before any typed conversion.
fn parseTree(allocator: Allocator, source: []const u8, options: ParseOptions) ParseError!Value {
    var parser: Parser = .init(allocator, source, options.diagnostics);
    return parser.parse();
}

test "parse a small document" {
    const source =
        \\// a comment
        \\{
        \\    name: 'json5',
        \\    version: 1.5,
        \\    hex: 0x10,
        \\    tags: ['parse', 'write',],
        \\    nothing: null,
        \\}
    ;
    var parsed = try parseFromSlice(Value, testing.allocator, source, .init);
    defer parsed.deinit();

    const root = parsed.value.object;
    try testing.expectEqualStrings("json5", root.get("name").?.string);
    try testing.expectEqual(@as(f64, 1.5), root.get("version").?.float);
    try testing.expectEqual(@as(i64, 16), root.get("hex").?.integer);
    try testing.expectEqual(@as(usize, 2), root.get("tags").?.array.items.len);
    try testing.expectEqualStrings("write", root.get("tags").?.array.items[1].string);
    try testing.expectEqual(Value.null, root.get("nothing").?);
}

test "a syntax error fills the diagnostics the caller passed" {
    var diagnostics: Diagnostics = undefined;
    try testing.expectError(
        error.SyntaxError,
        parseFromSlice(Value, testing.allocator, "{\n  a: 1,\n  b: ,\n}\n", .{
            .diagnostics = &diagnostics,
            .json = .{},
        }),
    );
    try testing.expectEqual(@as(u32, 3), diagnostics.line);
    try testing.expectEqual(@as(u32, 6), diagnostics.column);
    try testing.expectEqual(@as(u32, 15), diagnostics.span.start);
    try testing.expectEqual(@as(u32, 16), diagnostics.span.end);
    try testing.expectEqualStrings("expected a value", diagnostics.message());
}

test "a successful parse leaves the diagnostics alone" {
    var diagnostics: Diagnostics = .init;
    diagnostics.line = 99;
    diagnostics.column = 7;
    var parsed = try parseFromSlice(Value, testing.allocator, "1", .{
        .diagnostics = &diagnostics,
        .json = .{},
    });
    defer parsed.deinit();
    try testing.expectEqual(@as(u32, 99), diagnostics.line);
    try testing.expectEqual(@as(u32, 7), diagnostics.column);
}

test "a repeated name keeps the last value" {
    var parsed = try parseFromSlice(Value, testing.allocator, "{ a: 1, a: 2, b: 3 }", .init);
    defer parsed.deinit();
    const root = parsed.value.object;
    try testing.expectEqual(@as(i64, 2), root.get("a").?.integer);
    try testing.expectEqual(@as(usize, 2), root.count());
}

test "a parsed array can grow in its arena" {
    var parsed = try parseFromSlice(Value, testing.allocator, "[1]", .init);
    defer parsed.deinit();
    // Appending goes back through the arena the tree was built with, and
    // `Parsed.deinit` frees what it allocates.
    try parsed.value.array.append(.{ .integer = 2 });
    try testing.expectEqual(@as(usize, 2), parsed.value.array.items.len);
    try testing.expectEqual(@as(i64, 2), parsed.value.array.items[1].integer);
}

test "the tree does not borrow the source" {
    const allocator = testing.allocator;
    const source = try allocator.dupe(u8, "{ key: 'value' }");
    var parsed = try parseFromSlice(Value, allocator, source, .init);
    allocator.free(source);
    defer parsed.deinit();
    const root = parsed.value.object;
    try testing.expectEqualStrings("value", root.get("key").?.string);
}

test "parseFromSliceLeaky writes into the caller's allocator" {
    var arena: ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const value = try parseFromSliceLeaky(Value, arena.allocator(), "[1, 2, 3]", .init);
    try testing.expectEqual(@as(usize, 3), value.array.items.len);
    try testing.expectEqual(@as(i64, 3), value.array.items[2].integer);
}

test "string escapes" {
    const source =
        \\{
        \\    plain: 'hello',
        \\    hex: "\x41\u00f8",
        \\    special: "\b\f\n\r\t\v\0",
        \\    escaped: "\\\"\'\/",
        \\    unknown: "a\qb",
        \\    pair: "\uD83C\uDFBC",
        \\}
    ;
    var parsed = try parseFromSlice(Value, testing.allocator, source, .init);
    defer parsed.deinit();
    const root = parsed.value.object;
    try testing.expectEqualStrings("hello", root.get("plain").?.string);
    try testing.expectEqualStrings("A\u{f8}", root.get("hex").?.string);
    try testing.expectEqualStrings("\x08\x0c\n\r\t\x0b\x00", root.get("special").?.string);
    try testing.expectEqualStrings("\\\"'/", root.get("escaped").?.string);
    try testing.expectEqualStrings("aqb", root.get("unknown").?.string);
    try testing.expectEqualStrings("\u{1F3BC}", root.get("pair").?.string);
}

test "a string continues on the next line" {
    const source =
        \\{
        \\    lf: 'line 1 \
        \\line 2',
        \\    crlf: "line 1 \
        \\line 2",
        \\    cr: 'a\
        \\b',
        \\}
    ;
    var parsed = try parseFromSlice(Value, testing.allocator, source, .init);
    defer parsed.deinit();
    const root = parsed.value.object;
    try testing.expectEqualStrings("line 1 line 2", root.get("lf").?.string);
    try testing.expectEqualStrings("line 1 line 2", root.get("crlf").?.string);
    try testing.expectEqualStrings("ab", root.get("cr").?.string);
}

test "a string may hold a raw carriage return only in a continuation" {
    var diagnostics: Diagnostics = undefined;
    try testing.expectError(
        error.SyntaxError,
        parseFromSlice(Value, testing.allocator, "a: \"line 1 \rline 2\"", .{
            .diagnostics = &diagnostics,
            .json = .{},
        }),
    );
}

test "unquoted names" {
    const source =
        \\{
        \\    $: 1,
        \\    _: 2,
        \\    one1: 3,
        \\    ümläüt: 4,
        \\    sig\u03A3ma: 5,
        \\    while: 6,
        \\}
    ;
    var parsed = try parseFromSlice(Value, testing.allocator, source, .init);
    defer parsed.deinit();
    const root = parsed.value.object;
    try testing.expectEqual(@as(i64, 1), root.get("$").?.integer);
    try testing.expectEqual(@as(i64, 2), root.get("_").?.integer);
    try testing.expectEqual(@as(i64, 3), root.get("one1").?.integer);
    try testing.expectEqual(@as(i64, 4), root.get("ümläüt").?.integer);
    try testing.expectEqual(@as(i64, 5), root.get("sig\u{3A3}ma").?.integer);
    try testing.expectEqual(@as(i64, 6), root.get("while").?.integer);
}

test "a name accepts the ASCII subset and any non-ASCII code point" {
    const source =
        \\{
        \\    Ümläüt: 1,
        \\    $x: 2,
        \\    _: 3,
        \\    aδ: 4,
        \\    sig\u03A3ma: 5,
        \\    \uD801\uDC00: 6,
        \\    a\u200Cb: 7,
        \\}
    ;
    var parsed = try parseFromSlice(Value, testing.allocator, source, .init);
    defer parsed.deinit();
    const root = parsed.value.object;
    try testing.expectEqual(@as(i64, 1), root.get("Ümläüt").?.integer);
    try testing.expectEqual(@as(i64, 2), root.get("$x").?.integer);
    try testing.expectEqual(@as(i64, 3), root.get("_").?.integer);
    try testing.expectEqual(@as(i64, 4), root.get("aδ").?.integer);
    try testing.expectEqual(@as(i64, 5), root.get("sig\u{3A3}ma").?.integer);
    try testing.expectEqual(@as(i64, 6), root.get("\u{10400}").?.integer);
    try testing.expectEqual(@as(i64, 7), root.get("a\u{200C}b").?.integer);
}

test "a name rejects a digit and a lone surrogate" {
    const cases = [_][]const u8{
        "{ 1a: 1 }",
        "{ \\uD800: 1 }", // a lone high surrogate
        "{ a\\uDC00: 1 }", // a lone low surrogate
    };
    for (cases) |source| {
        var diagnostics: Diagnostics = undefined;
        try testing.expectError(error.SyntaxError, parseFromSlice(
            Value,
            testing.allocator,
            source,
            .{ .diagnostics = &diagnostics, .json = .{} },
        ));
        try testing.expect(diagnostics.message().len != 0);
    }
}

test "number mapping" {
    const source =
        \\{
        \\    a: 15,
        \\    b: 0x10,
        \\    c: .5,
        \\    d: 5.,
        \\    e: +2,
        \\    f: -0,
        \\    g: 2e23,
        \\    h: 0xFFFFFFFFFFFFFFFF,
        \\    i: Infinity,
        \\    j: -Infinity,
        \\    k: NaN,
        \\    l: 99999999999999999999,
        \\}
    ;
    var parsed = try parseFromSlice(Value, testing.allocator, source, .init);
    defer parsed.deinit();
    const root = parsed.value.object;
    try testing.expectEqual(@as(i64, 15), root.get("a").?.integer);
    try testing.expectEqual(@as(i64, 16), root.get("b").?.integer);
    try testing.expectEqual(@as(f64, 0.5), root.get("c").?.float);
    try testing.expectEqual(@as(f64, 5.0), root.get("d").?.float);
    try testing.expectEqual(@as(i64, 2), root.get("e").?.integer);
    try testing.expectEqual(@as(f64, 0.0), root.get("f").?.float);
    try testing.expect(std.math.signbit(root.get("f").?.float));
    try testing.expectEqual(@as(f64, 2e23), root.get("g").?.float);
    try testing.expectEqual(@as(f64, 18446744073709551616.0), root.get("h").?.float);
    try testing.expect(std.math.isInf(root.get("i").?.float));
    try testing.expect(std.math.isInf(root.get("j").?.float));
    try testing.expect(root.get("j").?.float < 0);
    try testing.expect(std.math.isNan(root.get("k").?.float));
    // A number too large for i64 is a float, never `.number_string`.
    try testing.expectEqual(@as(f64, 1e20), root.get("l").?.float);
}

test "the number edges" {
    const source = "{ a: +NaN, b: -0x8000000000000000, c: -0xFFFFFFFFFFFFFFFF, d: -0x0 }";
    var parsed = try parseFromSlice(Value, testing.allocator, source, .init);
    defer parsed.deinit();
    const root = parsed.value.object;
    try testing.expect(std.math.isNan(root.get("a").?.float));
    try testing.expectEqual(std.math.minInt(i64), root.get("b").?.integer);
    try testing.expect(root.get("c").?.float < 0);
    try testing.expect(std.math.signbit(root.get("d").?.float));
}

test "a line continuation accepts U+2028" {
    var parsed = try parseFromSlice(Value, testing.allocator, "'one \\\u{2028}two'", .init);
    defer parsed.deinit();
    try testing.expectEqualStrings("one two", parsed.value.string);
}

test "the source must be UTF-8" {
    inline for (.{ "\xFF", "\"\xFF\"" }) |source| {
        try testing.expectError(
            error.SyntaxError,
            parseFromSlice(Value, testing.allocator, source, .init),
        );
    }
}

test "comments and extra whitespace" {
    const source =
        "\xEF\xBB\xBF{\u{00A0}/* a block comment */ a: 1, // a line comment\n" ++
        "\u{2028}b: 2\u{2029}\x0C}\u{FEFF}";
    var parsed = try parseFromSlice(Value, testing.allocator, source, .init);
    defer parsed.deinit();
    const root = parsed.value.object;
    try testing.expectEqual(@as(i64, 1), root.get("a").?.integer);
    try testing.expectEqual(@as(i64, 2), root.get("b").?.integer);
}

test "a block comment does not nest" {
    var parsed = try parseFromSlice(Value, testing.allocator, "true /*/* /*/", .init);
    defer parsed.deinit();
    try testing.expectEqual(Value{ .bool = true }, parsed.value);
}

test "the sources that must fail" {
    const cases = [_][]const u8{
        "",
        "   ",
        "// only a comment",
        "/* only a comment */",
        "{",
        "[1,",
        "[,1]",
        "{,}",
        "{ a: 1 b: 2 }",
        "01",
        "-0123",
        "0x",
        ".",
        "1e",
        "1e2.3",
        "\"abc",
        "\"a\nb\"",
        "truex",
        "{ 10twenty: 1 }",
        "{ multi-word: 1 }",
        "\"\\01\"",
        "\"\\8\"",
        "\"\\x1\"",
        "\"\\uD800\"",
        "\"\\uDC00\"",
        "{ a: 1 } garbage",
        "/* unterminated",
        "\"\\",
    };
    for (cases) |source| {
        var diagnostics: Diagnostics = undefined;
        const result = parseFromSlice(Value, testing.allocator, source, .{
            .diagnostics = &diagnostics,
            .json = .{},
        });
        try testing.expectError(error.SyntaxError, result);
        try testing.expect(diagnostics.message().len != 0);
        try testing.expect(diagnostics.line >= 1);
        try testing.expect(diagnostics.column >= 1);
        try testing.expect(diagnostics.span.start <= diagnostics.span.end);
        try testing.expect(diagnostics.span.end <= source.len);
    }
}

test "an unpaired surrogate is a string error" {
    var diagnostics: Diagnostics = undefined;
    try testing.expectError(
        error.SyntaxError,
        parseFromSlice(Value, testing.allocator, "\"\\uD800x\"", .{
            .diagnostics = &diagnostics,
            .json = .{},
        }),
    );
    try testing.expectEqual(@as(u32, 2), diagnostics.column);
}

test "a value nested past the limit is a diagnostic" {
    var source: [1024]u8 = undefined;
    @memset(&source, '[');
    @memset(source[257..], ']');
    try testing.expectError(
        error.SyntaxError,
        parseFromSlice(Value, testing.allocator, source[0..514], .init),
    );
}

/// `Stringify.Options.init` with one knob changed, for the tests below.
const indent_2: Stringify.Options = .{
    .allow_nonfinite = true,
    .whitespace = .indent_2,
    .emit_null_optional_fields = true,
    .emit_strings_as_arrays = false,
    .escape_unicode = false,
    .emit_nonportable_numbers_as_strings = false,
};
const escaped: Stringify.Options = .{
    .allow_nonfinite = true,
    .whitespace = .minified,
    .emit_null_optional_fields = true,
    .emit_strings_as_arrays = false,
    .escape_unicode = true,
    .emit_nonportable_numbers_as_strings = false,
};
const no_nonfinite: Stringify.Options = .{
    .allow_nonfinite = false,
    .whitespace = .minified,
    .emit_null_optional_fields = true,
    .emit_strings_as_arrays = false,
    .escape_unicode = false,
    .emit_nonportable_numbers_as_strings = false,
};

test "the writer emits minified JSON" {
    const source = "{ a: 1, b: [true, null, 'x'], c: 1.5 }";
    var parsed = try parseFromSlice(Value, testing.allocator, source, .init);
    defer parsed.deinit();

    var output: Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    try Stringify.value(parsed.value, .init, &output.writer);
    try testing.expectEqualStrings("{\"a\":1,\"b\":[true,null,\"x\"],\"c\":1.5}", output.written());
}

test "the writer indents" {
    const source = "{ a: 1, b: [true, null] }";
    var parsed = try parseFromSlice(Value, testing.allocator, source, .init);
    defer parsed.deinit();

    var output: Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    try Stringify.value(parsed.value, indent_2, &output.writer);
    try testing.expectEqualStrings(
        \\{
        \\  "a": 1,
        \\  "b": [
        \\    true,
        \\    null
        \\  ]
        \\}
    , output.written());
}

test "the writer escapes non-ASCII on request" {
    var parsed = try parseFromSlice(Value, testing.allocator, "'é'", .init);
    defer parsed.deinit();

    var output: Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    try Stringify.value(parsed.value, escaped, &output.writer);
    try testing.expectEqualStrings("\"\\u00e9\"", output.written());
}

test "the writer spells a non-finite float as JSON5" {
    inline for (.{ "NaN", "Infinity", "-Infinity" }) |source| {
        var parsed = try parseFromSlice(Value, testing.allocator, source, .init);
        defer parsed.deinit();

        var output: Io.Writer.Allocating = .init(testing.allocator);
        defer output.deinit();
        try Stringify.value(parsed.value, .init, &output.writer);
        try testing.expectEqualStrings(source, output.written());

        try testing.expectError(
            error.NonFiniteFloat,
            Stringify.value(parsed.value, no_nonfinite, &output.writer),
        );
    }
}

test "the writer keeps an integral float a float" {
    var parsed = try parseFromSlice(Value, testing.allocator, "1.0", .init);
    defer parsed.deinit();
    try testing.expect(parsed.value == .float);

    var output: Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    try Stringify.value(parsed.value, .init, &output.writer);
    try testing.expectEqualStrings("1.0", output.written());

    var again = try parseFromSlice(Value, testing.allocator, output.written(), .init);
    defer again.deinit();
    try testing.expect(again.value == .float);
}

test "the writer copies number_string bytes" {
    const value: Value = .{ .number_string = "1e999" };
    var output: Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    try Stringify.value(value, .init, &output.writer);
    try testing.expectEqualStrings("1e999", output.written());
}

test "the writer stops on a tree that nests too deep" {
    var arena: ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var value: Value = .null;
    for (0..257) |_| {
        var array: Array = .init(arena.allocator());
        try array.append(value);
        value = .{ .array = array };
    }
    var output: Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    try testing.expectError(
        error.NestingTooDeep,
        Stringify.value(value, .init, &output.writer),
    );
}

test "a document round-trips through the writer" {
    const source =
        \\{
        \\    unquoted: 'and you can quote me on that',
        \\    singleQuotes: 'I can use "double quotes" here',
        \\    lineBreaks: "Look, Mom! \
        \\No \\n's!",
        \\    hexadecimal: 0xdecaf,
        \\    leadingDecimalPoint: .8675309, andTrailing: 8675309.,
        \\    positiveSign: +1,
        \\    trailingComma: 'in objects', andIn: ['arrays',],
        \\    "backwardsCompatible": "with JSON",
        \\}
    ;
    var first = try parseFromSlice(Value, testing.allocator, source, .init);
    defer first.deinit();

    var output: Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    try Stringify.value(first.value, indent_2, &output.writer);

    var second = try parseFromSlice(Value, testing.allocator, output.written(), .init);
    defer second.deinit();
    try testing.expect(sameValue(first.value, second.value));
}

const Speed = enum { fast, slow };

const Shape = union(Speed) {
    fast: u32,
    slow: struct { delay: f64 },
};

const Release = struct {
    major: u16,
    minor: u16,

    pub fn jsonStringify(self: Release, jws: anytype) !void {
        try jws.print("\"{d}.{d}\"", .{ self.major, self.minor });
    }

    pub fn jsonParseFromValue(
        _: Allocator,
        source: Value,
        _: std.json.ParseOptions,
    ) !Release {
        if (source != .string) return error.UnexpectedToken;
        const dot = std.mem.findScalar(u8, source.string, '.') orelse
            return error.InvalidCharacter;
        return .{
            .major = try std.fmt.parseInt(u16, source.string[0..dot], 10),
            .minor = try std.fmt.parseInt(u16, source.string[dot + 1 ..], 10),
        };
    }
};

const Config = struct {
    name: []const u8,
    retry: ?u32 = null,
    speed: Speed,
    shape: Shape,
    tags: []const []const u8,
    version: Release,
};

test "a typed value round-trips" {
    const source =
        \\{
        \\    name: 'json5',
        \\    retry: null,
        \\    speed: 'slow',
        \\    shape: { slow: { delay: 1.5 } },
        \\    tags: ['a', 'b'],
        \\    version: '0.2',
        \\}
    ;
    var first = try parseFromSlice(Config, testing.allocator, source, .init);
    defer first.deinit();
    try testing.expectEqualStrings("json5", first.value.name);
    try testing.expectEqual(@as(?u32, null), first.value.retry);
    try testing.expectEqual(Speed.slow, first.value.speed);
    try testing.expectEqual(@as(f64, 1.5), first.value.shape.slow.delay);
    try testing.expectEqual(@as(usize, 2), first.value.tags.len);
    try testing.expectEqualStrings("b", first.value.tags[1]);
    try testing.expectEqual(Release{ .major = 0, .minor = 2 }, first.value.version);

    var output: Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    try Stringify.value(first.value, .init, &output.writer);

    var second = try parseFromSlice(Config, testing.allocator, output.written(), .init);
    defer second.deinit();
    try testing.expectEqualDeep(first.value, second.value);
}

test "a NaN in a struct follows allow_nonfinite" {
    const Sample = struct {
        value: f64,
        label: []const u8,
    };
    const source = "{ value: NaN, label: 'x' }";
    var parsed = try parseFromSlice(Sample, testing.allocator, source, .init);
    defer parsed.deinit();
    try testing.expect(std.math.isNan(parsed.value.value));

    var output: Io.Writer.Allocating = .init(testing.allocator);
    defer output.deinit();
    try Stringify.value(parsed.value, .init, &output.writer);
    try testing.expectEqualStrings("{\"value\":NaN,\"label\":\"x\"}", output.written());
    try testing.expectError(
        error.NonFiniteFloat,
        Stringify.value(parsed.value, no_nonfinite, &output.writer),
    );
}

test "the typed pass reads options.json" {
    const Strict = struct { a: i64 };
    try testing.expectError(
        error.UnknownField,
        parseFromSlice(Strict, testing.allocator, "{ a: 1, b: 2 }", .init),
    );
    var parsed = try parseFromSlice(Strict, testing.allocator, "{ a: 1, b: 2 }", .{
        .diagnostics = null,
        .json = .{ .ignore_unknown_fields = true },
    });
    defer parsed.deinit();
    try testing.expectEqual(@as(i64, 1), parsed.value.a);
}

test "the tree type skips the typed pass" {
    var parsed = try parseFromSlice(Value, testing.allocator, "{ a: [1, 2] }", .init);
    defer parsed.deinit();
    try testing.expect(parsed.value == .object);
    const items = parsed.value.object.get("a").?.array.items;
    try testing.expectEqual(@as(i64, 2), items[1].integer);
}

fn sameValue(a: Value, b: Value) bool {
    if (std.meta.activeTag(a) != std.meta.activeTag(b)) return false;
    return switch (a) {
        .null => true,
        .bool => |x| x == b.bool,
        .integer => |x| x == b.integer,
        .float => |x| (std.math.isNan(x) and std.math.isNan(b.float)) or x == b.float,
        .number_string => |x| std.mem.eql(u8, x, b.number_string),
        .string => |x| std.mem.eql(u8, x, b.string),
        .array => |x| blk: {
            if (x.items.len != b.array.items.len) break :blk false;
            for (x.items, b.array.items) |item, other| {
                if (!sameValue(item, other)) break :blk false;
            }
            break :blk true;
        },
        .object => |x| blk: {
            if (x.count() != b.object.count()) break :blk false;
            var it = x.iterator();
            while (it.next()) |entry| {
                const other = b.object.get(entry.key_ptr.*) orelse break :blk false;
                if (!sameValue(entry.value_ptr.*, other)) break :blk false;
            }
            break :blk true;
        },
    };
}
