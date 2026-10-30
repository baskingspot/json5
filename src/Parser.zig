//! The JSON5 reader: source bytes in, a `std.json.Value` tree out, or a
//! diagnostic.
//!
//! The grammar is https://spec.json5.org. It reads one top-level value and
//! requires the source to end after it. Every string and key is copied into
//! the allocator, so the caller may free the source as soon as `parse`
//! returns.

const std = @import("std");
const math = std.math;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Diagnostics = @import("Diagnostics.zig");
const Span = Diagnostics.Span;

const Array = std.json.Array;
const ObjectMap = std.json.ObjectMap;
const Value = std.json.Value;

const Parser = @This();

/// The parser's failures. A syntax error also fills in the diagnostics.
pub const Error = error{ SyntaxError, OutOfMemory };

/// How deep objects and arrays may nest. A deeper document is a syntax error,
/// so recursive descent cannot overflow the stack on hostile input.
const max_depth = 256;

const line_separator_message = "U+2028 and U+2029 must be escaped in a string";
const name_escape_message = "a name escape is `\\u` and four hexadecimal digits";
const string_line_message = "a string cannot span lines without a backslash";
const string_end_message = "the string does not end";
const surrogate_pair_message = "a high surrogate needs a low surrogate after it";
const unicode_escape_message = "`\\u` needs four hexadecimal digits";

source: []const u8,
index: usize,
allocator: Allocator,
diagnostics: ?*Diagnostics,
/// Stands in when the caller passed none, so the failure path has one shape.
fallback: Diagnostics,
depth: u32,

/// A line and a byte column, both counted from one.
const Position = struct {
    line: u32,
    column: u32,
};

/// One decoded UTF-8 sequence: the code point and the bytes it came from.
const Sequence = struct {
    cp: u21,
    len: u8,
};

/// Prepare to parse `source`. Every value, string, and container is allocated
/// from `allocator`, usually an arena's. A syntax error is written to
/// `diagnostics` when it is not null.
pub fn init(allocator: Allocator, source: []const u8, diagnostics: ?*Diagnostics) Parser {
    return .{
        .source = source,
        .index = 0,
        .allocator = allocator,
        .diagnostics = diagnostics,
        .fallback = .init,
        .depth = 0,
    };
}

/// Parse the whole source. On `error.SyntaxError`, the diagnostics say where
/// and why. `error.OutOfMemory` leaves them untouched.
pub fn parse(self: *Parser) Error!Value {
    if (self.source.len > math.maxInt(u32)) {
        const diagnostics = self.report();
        diagnostics.* = .init;
        diagnostics.setMessage("the source is longer than 4 GiB", .{});
        return error.SyntaxError;
    }
    try self.checkUtf8();
    try self.skipWhitespace();
    const value = try self.parseValue();
    try self.skipWhitespace();
    if (!self.atEnd()) {
        return self.failAt(
            self.index,
            self.index + 1,
            "unexpected bytes after the top-level value",
            .{},
        );
    }
    return value;
}

// Values

fn parseValue(self: *Parser) Error!Value {
    try self.skipWhitespace();
    if (self.atEnd()) {
        return self.failAt(
            self.index,
            self.index,
            "expected a value, found the end of the source",
            .{},
        );
    }
    return switch (self.source[self.index]) {
        '{' => self.parseObject(),
        '[' => self.parseArray(),
        '"', '\'' => .{ .string = try self.parseString() },
        't' => self.parseKeyword("true", .{ .bool = true }),
        'f' => self.parseKeyword("false", .{ .bool = false }),
        'n' => self.parseKeyword("null", .null),
        '+', '-', '.', '0'...'9', 'I', 'N' => self.parseNumber(),
        else => self.failAt(self.index, self.index + 1, "expected a value", .{}),
    };
}

fn parseKeyword(self: *Parser, comptime word: []const u8, value: Value) Error!Value {
    if (!mem.startsWith(u8, self.source[self.index..], word)) {
        return self.failAt(self.index, self.index + word.len, "expected `{s}`", .{word});
    }
    self.index += word.len;
    if (!self.atEnd()) {
        const next = self.source[self.index];
        const cp: u21 = if (next < 0x80) next else self.sequenceAt(self.index).cp;
        if (isName(cp, false)) {
            return self.failAt(
                self.index - word.len,
                self.index + 1,
                "`{s}` is followed by a name character",
                .{word},
            );
        }
    }
    return value;
}

fn parseObject(self: *Parser) Error!Value {
    self.index += 1;
    try self.enter();
    defer self.depth -= 1;

    var object: ObjectMap = .empty;
    try self.skipWhitespace();
    if (self.eat('}')) return .{ .object = object };
    while (true) {
        const name = try self.parseMemberName();
        try self.skipWhitespace();
        if (!self.eat(':')) {
            return self.failAt(self.index, self.index + 1, "expected `:` after the name", .{});
        }
        const item = try self.parseValue();
        // A repeated name keeps the first position and the last value, which
        // is what a JavaScript object does.
        try object.put(self.allocator, name, item);
        try self.skipWhitespace();
        if (self.eat('}')) return .{ .object = object };
        if (!self.eat(',')) {
            return self.failAt(self.index, self.index + 1, "expected `,` or `}}`", .{});
        }
        try self.skipWhitespace();
        if (self.eat('}')) return .{ .object = object };
    }
}

fn parseArray(self: *Parser) Error!Value {
    self.index += 1;
    try self.enter();
    defer self.depth -= 1;

    var array: Array = .init(self.allocator);
    try self.skipWhitespace();
    if (self.eat(']')) return .{ .array = array };
    while (true) {
        try array.append(try self.parseValue());
        try self.skipWhitespace();
        if (self.eat(']')) return .{ .array = array };
        if (!self.eat(',')) {
            return self.failAt(self.index, self.index + 1, "expected `,` or `]`", .{});
        }
        try self.skipWhitespace();
        if (self.eat(']')) return .{ .array = array };
    }
}

fn parseMemberName(self: *Parser) Error![]const u8 {
    try self.skipWhitespace();
    if (self.atEnd()) {
        return self.failAt(
            self.index,
            self.index,
            "expected a name, found the end of the source",
            .{},
        );
    }
    return switch (self.source[self.index]) {
        '"', '\'' => self.parseString(),
        else => self.parseIdentifier(),
    };
}

// Strings

fn parseString(self: *Parser) Error![]const u8 {
    const quote = self.source[self.index];
    const start = self.index + 1;
    var i = start;
    while (i < self.source.len) {
        const c = self.source[i];
        if (c == quote) {
            self.index = i + 1;
            return self.allocator.dupe(u8, self.source[start..i]);
        }
        if (c == '\\') {
            self.index = i;
            return self.parseEscapedString(quote, start);
        }
        if (c == '\n' or c == '\r') {
            return self.failAt(i, i + 1, string_line_message, .{});
        }
        if (c < 0x80) {
            i += 1;
            continue;
        }
        const sequence = self.sequenceAt(i);
        if (sequence.cp == 0x2028 or sequence.cp == 0x2029) {
            return self.failAt(i, i + sequence.len, line_separator_message, .{});
        }
        i += sequence.len;
    }
    return self.failAt(start - 1, self.source.len, string_end_message, .{});
}

fn parseEscapedString(self: *Parser, quote: u8, start: usize) Error![]const u8 {
    var out: ArrayList(u8) = .empty;
    errdefer out.deinit(self.allocator);
    try out.appendSlice(self.allocator, self.source[start..self.index]);
    while (!self.atEnd()) {
        const c = self.source[self.index];
        if (c == quote) {
            self.index += 1;
            return out.toOwnedSlice(self.allocator);
        }
        if (c == '\\') {
            try self.appendEscape(&out);
            continue;
        }
        if (c == '\n' or c == '\r') {
            return self.failAt(self.index, self.index + 1, string_line_message, .{});
        }
        if (c < 0x80) {
            try out.append(self.allocator, c);
            self.index += 1;
            continue;
        }
        const sequence = self.sequenceAt(self.index);
        if (sequence.cp == 0x2028 or sequence.cp == 0x2029) {
            return self.failAt(self.index, self.index + sequence.len, line_separator_message, .{});
        }
        try out.appendSlice(self.allocator, self.source[self.index..][0..sequence.len]);
        self.index += sequence.len;
    }
    return self.failAt(start - 1, self.source.len, string_end_message, .{});
}

fn appendEscape(self: *Parser, out: *ArrayList(u8)) Error!void {
    const backslash = self.index;
    self.index += 1;
    if (self.atEnd()) return self.failAt(backslash, self.source.len, string_end_message, .{});
    const c = self.source[self.index];
    self.index += 1;
    switch (c) {
        '\'', '"', '\\', '/' => try out.append(self.allocator, c),
        'b' => try out.append(self.allocator, 0x08),
        'f' => try out.append(self.allocator, 0x0C),
        'n' => try out.append(self.allocator, '\n'),
        'r' => try out.append(self.allocator, '\r'),
        't' => try out.append(self.allocator, '\t'),
        'v' => try out.append(self.allocator, 0x0B),
        '0' => {
            if (!self.atEnd() and std.ascii.isDigit(self.source[self.index])) {
                return self.failAt(
                    backslash,
                    self.index + 1,
                    "`\\0` cannot be followed by a digit",
                    .{},
                );
            }
            try out.append(self.allocator, 0);
        },
        '1'...'9' => return self.failAt(
            backslash,
            self.index,
            "`\\{c}` is not a JSON5 escape",
            .{c},
        ),
        'x' => {
            const cp = try self.readHex(backslash, 2, "`\\x` needs two hexadecimal digits");
            try self.appendCodepoint(out, cp);
        },
        'u' => {
            const escape = try self.unicodeEscapeAt(backslash, unicode_escape_message);
            self.index = backslash + escape.len;
            try self.appendCodepoint(out, escape.cp);
        },
        '\n' => {},
        '\r' => if (!self.atEnd() and self.source[self.index] == '\n') {
            self.index += 1;
        },
        else => if (c < 0x80) {
            // Any other ASCII character stands for itself; `\q` is `q`.
            try out.append(self.allocator, c);
        } else {
            self.index -= 1;
            const sequence = self.sequenceAt(self.index);
            if (sequence.cp == 0x2028 or sequence.cp == 0x2029) {
                self.index += sequence.len;
                return;
            }
            try out.appendSlice(self.allocator, self.source[self.index..][0..sequence.len]);
            self.index += sequence.len;
        },
    }
}

/// One `\uXXXX`, or `\uXXXX\uXXXX` when the first half is a high surrogate.
/// The bytes start at `at`, which is the backslash. The parser does not move.
const Escape = struct {
    cp: u21,
    /// Six bytes for one escape, twelve for a surrogate pair.
    len: u8,
};

fn unicodeEscapeAt(
    self: *Parser,
    at: usize,
    comptime message: []const u8,
) Error!Escape {
    if (at + 6 > self.source.len or self.source[at] != '\\' or self.source[at + 1] != 'u') {
        return self.failAt(at, @min(at + 2, self.source.len), message, .{});
    }
    const first = hex4(self.source[at + 2 .. at + 6]) orelse {
        return self.failAt(at, at + 6, message, .{});
    };
    if (first >= 0xDC00 and first <= 0xDFFF) {
        return self.failAt(
            at,
            at + 6,
            "a low surrogate needs a high surrogate before it",
            .{},
        );
    }
    if (first < 0xD800 or first > 0xDBFF) return .{ .cp = first, .len = 6 };
    if (at + 12 > self.source.len or
        self.source[at + 6] != '\\' or self.source[at + 7] != 'u')
    {
        return self.failAt(at, at + 6, surrogate_pair_message, .{});
    }
    const low = hex4(self.source[at + 8 .. at + 12]) orelse {
        return self.failAt(at, at + 12, message, .{});
    };
    if (low < 0xDC00 or low > 0xDFFF) {
        return self.failAt(at + 6, at + 12, surrogate_pair_message, .{});
    }
    return .{
        .cp = 0x10000 + ((first - 0xD800) << 10) + (low - 0xDC00),
        .len = 12,
    };
}

fn readHex(
    self: *Parser,
    backslash: usize,
    comptime count: u8,
    comptime message: []const u8,
) Error!u21 {
    var value: u21 = 0;
    var i: u8 = 0;
    while (i < count) : (i += 1) {
        if (self.atEnd()) return self.failAt(backslash, self.source.len, message, .{});
        const digit = std.fmt.charToDigit(self.source[self.index], 16) catch {
            return self.failAt(backslash, self.index + 1, message, .{});
        };
        value = value * 16 + @as(u21, digit);
        self.index += 1;
    }
    return value;
}

fn appendCodepoint(self: *Parser, out: *ArrayList(u8), cp: u21) Error!void {
    var buffer: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(cp, &buffer) catch {
        return self.failAt(self.index, self.index, "`\\u` names a surrogate half", .{});
    };
    try out.appendSlice(self.allocator, buffer[0..len]);
}

// Names

fn parseIdentifier(self: *Parser) Error![]const u8 {
    const start = self.index;
    var i = start;
    var first = true;
    var escaped = false;
    while (i < self.source.len) {
        const c = self.source[i];
        if (c == '\\') {
            if (i + 1 >= self.source.len or self.source[i + 1] != 'u') {
                return self.failAt(i, @min(i + 2, self.source.len), name_escape_message, .{});
            }
            const escape = try self.unicodeEscapeAt(i, name_escape_message);
            if (!isName(escape.cp, first)) {
                return self.failAt(i, i + escape.len, "`\\u{X:0>4}` cannot {s} a name", .{
                    escape.cp,
                    if (first) "start" else "continue",
                });
            }
            escaped = true;
            i += escape.len;
        } else if (c < 0x80) {
            if (!isName(c, first)) break;
            i += 1;
        } else {
            const sequence = self.sequenceAt(i);
            if (!isName(sequence.cp, first)) break;
            i += sequence.len;
        }
        first = false;
    }
    if (first) {
        if (start == self.source.len) {
            return self.failAt(start, start, "expected a name, found the end of the source", .{});
        }
        const c = self.source[start];
        if (c >= 0x20 and c < 0x7F) {
            return self.failAt(start, start + 1, "expected a name, found `{c}`", .{c});
        }
        return self.failAt(start, start + 1, "expected a name", .{});
    }
    self.index = i;
    if (!escaped) return self.allocator.dupe(u8, self.source[start..i]);
    return self.decodeIdentifier(start, i);
}

/// Can `cp` appear at this point in a name? The ASCII part of ES5's
/// IdentifierStart and IdentifierPart, plus every non-ASCII code point. The
/// exact categories need a Unicode property table this package does not
/// vendor; `root.zig` states the limit.
fn isName(cp: u21, first: bool) bool {
    if (cp < 0x80) {
        return switch (cp) {
            'A'...'Z', 'a'...'z', '_', '$' => true,
            '0'...'9' => !first,
            else => false,
        };
    }
    return !(cp >= 0xD800 and cp <= 0xDFFF);
}

fn decodeIdentifier(self: *Parser, start: usize, end: usize) Error![]const u8 {
    var out: ArrayList(u8) = .empty;
    errdefer out.deinit(self.allocator);
    var i = start;
    while (i < end) {
        if (self.source[i] != '\\') {
            try out.append(self.allocator, self.source[i]);
            i += 1;
            continue;
        }
        const escape = try self.unicodeEscapeAt(i, name_escape_message);
        var buffer: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(escape.cp, &buffer) catch unreachable;
        try out.appendSlice(self.allocator, buffer[0..len]);
        i += escape.len;
    }
    return out.toOwnedSlice(self.allocator);
}

fn hex4(bytes: []const u8) ?u21 {
    var value: u21 = 0;
    for (bytes) |c| {
        const digit = std.fmt.charToDigit(c, 16) catch return null;
        value = value * 16 + @as(u21, digit);
    }
    return value;
}

// Numbers

/// Read one number into a `std.json.Value` tag. The tree never holds
/// `.number_string`: a value that does not fit `i64` is a float.
fn parseNumber(self: *Parser) Error!Value {
    const start = self.index;
    var negative = false;
    if (self.source[self.index] == '+' or self.source[self.index] == '-') {
        negative = self.source[self.index] == '-';
        self.index += 1;
    }
    if (self.atEnd()) {
        return self.failAt(start, self.index, "expected a number after the sign", .{});
    }

    if (mem.startsWith(u8, self.source[self.index..], "Infinity")) {
        self.index += "Infinity".len;
        return .{ .float = if (negative) -math.inf(f64) else math.inf(f64) };
    }
    if (mem.startsWith(u8, self.source[self.index..], "NaN")) {
        self.index += "NaN".len;
        return .{ .float = math.nan(f64) };
    }
    if (self.source[self.index] == '0' and self.index + 1 < self.source.len and
        (self.source[self.index + 1] == 'x' or self.source[self.index + 1] == 'X'))
    {
        self.index += 2;
        return self.parseHex(start, negative);
    }
    return self.parseDecimal(start);
}

fn parseHex(self: *Parser, start: usize, negative: bool) Error!Value {
    const digits = self.index;
    var magnitude: u64 = 0;
    var overflow = false;
    while (!self.atEnd()) {
        const digit = std.fmt.charToDigit(self.source[self.index], 16) catch break;
        if (!overflow) {
            if (magnitude > (math.maxInt(u64) - @as(u64, digit)) / 16) {
                overflow = true;
            } else {
                magnitude = magnitude * 16 + digit;
            }
        }
        self.index += 1;
    }
    if (self.index == digits) {
        return self.failAt(start, self.index, "`0x` needs at least one hexadecimal digit", .{});
    }
    // A negative zero is a float: `.integer` cannot carry the sign, and the
    // value is the IEEE -0, not the integer 0.
    if (magnitude == 0 and negative) return .{ .float = -0.0 };
    if (overflow) {
        var value: f64 = 0;
        for (self.source[digits..self.index]) |c| {
            const digit = std.fmt.charToDigit(c, 16) catch unreachable;
            value = value * 16 + @as(f64, @floatFromInt(digit));
        }
        return .{ .float = if (negative) -value else value };
    }
    if (negative) {
        if (magnitude == @as(u64, 1) << 63) return .{ .integer = math.minInt(i64) };
        if (magnitude <= math.maxInt(i64)) return .{ .integer = -@as(i64, @intCast(magnitude)) };
        return .{ .float = -@as(f64, @floatFromInt(magnitude)) };
    }
    if (magnitude <= math.maxInt(i64)) return .{ .integer = @intCast(magnitude) };
    return .{ .float = @floatFromInt(magnitude) };
}

fn parseDecimal(self: *Parser, start: usize) Error!Value {
    var digits: usize = 0;
    if (self.source[self.index] == '0') {
        self.index += 1;
        digits = 1;
        if (!self.atEnd() and std.ascii.isDigit(self.source[self.index])) {
            return self.failAt(
                start,
                self.index + 1,
                "a decimal number cannot have a leading zero",
                .{},
            );
        }
    } else if (self.source[self.index] >= '1' and self.source[self.index] <= '9') {
        while (!self.atEnd() and std.ascii.isDigit(self.source[self.index])) self.index += 1;
        digits = self.index - start;
    }

    var fraction = false;
    if (!self.atEnd() and self.source[self.index] == '.') {
        self.index += 1;
        fraction = true;
        const first = self.index;
        while (!self.atEnd() and std.ascii.isDigit(self.source[self.index])) self.index += 1;
        if (self.index == first and digits == 0) {
            return self.failAt(start, self.index, "a decimal point needs a digit", .{});
        }
    }
    if (digits == 0 and !fraction) {
        return self.failAt(start, self.index, "expected a number", .{});
    }

    var exponent = false;
    if (!self.atEnd() and (self.source[self.index] == 'e' or self.source[self.index] == 'E')) {
        self.index += 1;
        exponent = true;
        if (!self.atEnd() and (self.source[self.index] == '+' or self.source[self.index] == '-')) {
            self.index += 1;
        }
        const first = self.index;
        while (!self.atEnd() and std.ascii.isDigit(self.source[self.index])) self.index += 1;
        if (self.index == first) {
            return self.failAt(start, self.index, "an exponent needs a digit", .{});
        }
    }

    const text = self.source[start..self.index];
    if (!fraction and !exponent) {
        if (mem.eql(u8, text, "-0")) return .{ .float = -0.0 };
        const value = std.fmt.parseInt(i64, text, 10) catch |err| switch (err) {
            error.Overflow => return .{ .float = std.fmt.parseFloat(f64, text) catch unreachable },
            error.InvalidCharacter => unreachable,
        };
        return .{ .integer = value };
    }
    return .{ .float = std.fmt.parseFloat(f64, text) catch unreachable };
}

// Whitespace and comments

fn skipWhitespace(self: *Parser) Error!void {
    while (!self.atEnd()) {
        const c = self.source[self.index];
        switch (c) {
            ' ', '\t', '\n', '\r', 0x0B, 0x0C => self.index += 1,
            '/' => {
                if (self.index + 1 == self.source.len) return;
                switch (self.source[self.index + 1]) {
                    '/' => try self.skipLineComment(),
                    '*' => try self.skipBlockComment(),
                    else => return,
                }
            },
            else => {
                if (c < 0x80) return;
                const sequence = self.sequenceAt(self.index);
                if (!isSpaceSeparator(sequence.cp) and sequence.cp != 0xFEFF) return;
                self.index += sequence.len;
            },
        }
    }
}

fn skipLineComment(self: *Parser) Error!void {
    self.index += 2;
    while (!self.atEnd()) {
        const c = self.source[self.index];
        if (c == '\n' or c == '\r') return;
        if (c < 0x80) {
            self.index += 1;
            continue;
        }
        const sequence = self.sequenceAt(self.index);
        if (sequence.cp == 0x2028 or sequence.cp == 0x2029) return;
        self.index += sequence.len;
    }
}

fn skipBlockComment(self: *Parser) Error!void {
    const start = self.index;
    self.index += 2;
    // JSON5 block comments do not nest: the first `*/` ends one.
    const rest = self.source[self.index..];
    if (mem.find(u8, rest, "*/")) |offset| {
        self.index += offset + 2;
        return;
    }
    self.index = self.source.len;
    return self.failAt(start, self.source.len, "the block comment does not end", .{});
}

/// The Unicode Space Separator category, plus the two line separators. This is
/// the whole Zs list, not a range guess: NBSP, OGHAM SPACE MARK, the EN QUAD
/// through HAIR SPACE run, NARROW NO-BREAK SPACE, MEDIUM MATHEMATICAL SPACE,
/// and IDEOGRAPHIC SPACE.
fn isSpaceSeparator(cp: u21) bool {
    return switch (cp) {
        0x00A0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000 => true,
        else => false,
    };
}

// Scanning helpers

fn atEnd(self: *const Parser) bool {
    return self.index >= self.source.len;
}

fn eat(self: *Parser, c: u8) bool {
    if (self.atEnd() or self.source[self.index] != c) return false;
    self.index += 1;
    return true;
}

fn sequenceAt(self: *const Parser, offset: usize) Sequence {
    const len = std.unicode.utf8ByteSequenceLength(self.source[offset]) catch unreachable;
    var bytes: [4]u8 = @splat(0);
    @memcpy(bytes[0..len], self.source[offset..][0..len]);
    return .{ .cp = decodeSequence(bytes, len) orelse unreachable, .len = len };
}

/// Decode a sequence whose length is already known. `std.unicode.utf8Decode`
/// wants a slice and re-checks the length; the fixed-length decoders do not.
fn decodeSequence(bytes: [4]u8, len: u8) ?u21 {
    return switch (len) {
        1 => bytes[0],
        2 => std.unicode.utf8Decode2(bytes[0..2].*) catch null,
        3 => std.unicode.utf8Decode3(bytes[0..3].*) catch null,
        4 => std.unicode.utf8Decode4(bytes[0..4].*) catch null,
        else => null,
    };
}

fn enter(self: *Parser) Error!void {
    self.depth += 1;
    if (self.depth > max_depth) {
        return self.failAt(
            self.index,
            self.index + 1,
            "the value nests deeper than {d} levels",
            .{max_depth},
        );
    }
}

fn checkUtf8(self: *Parser) Error!void {
    var i: usize = 0;
    while (i < self.source.len) {
        const len: usize = std.unicode.utf8ByteSequenceLength(self.source[i]) catch {
            return self.failAt(i, i + 1, "the source is not valid UTF-8", .{});
        };
        if (i + len > self.source.len) {
            return self.failAt(i, self.source.len, "the source is not valid UTF-8", .{});
        }
        var bytes: [4]u8 = @splat(0);
        @memcpy(bytes[0..len], self.source[i..][0..len]);
        if (decodeSequence(bytes, @intCast(len)) == null) {
            return self.failAt(i, i + len, "the source is not valid UTF-8", .{});
        }
        i += len;
    }
}

// Failures

fn report(self: *Parser) *Diagnostics {
    return self.diagnostics orelse &self.fallback;
}

fn failAt(self: *Parser, start: usize, end: usize, comptime fmt: []const u8, args: anytype) Error {
    @branchHint(.cold);
    const diagnostics = self.report();
    const span: Span = .{
        .start = @intCast(@min(start, self.source.len)),
        .end = @intCast(@min(end, self.source.len)),
    };
    const position = positionAt(self.source, span.start);
    diagnostics.* = .init;
    diagnostics.span = span;
    diagnostics.line = position.line;
    diagnostics.column = position.column;
    diagnostics.setMessage(fmt, args);
    return error.SyntaxError;
}

fn positionAt(source: []const u8, offset: u32) Position {
    var line: u32 = 1;
    var line_start: u32 = 0;
    var i: u32 = 0;
    while (i < offset) : (i += 1) {
        switch (source[i]) {
            '\n' => {
                line += 1;
                line_start = i + 1;
            },
            '\r' => {
                line += 1;
                if (i + 1 < offset and source[i + 1] == '\n') i += 1;
                line_start = i + 1;
            },
            else => {},
        }
    }
    return .{ .line = line, .column = offset - line_start + 1 };
}
