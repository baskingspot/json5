//! Where a parse failed: the bytes, the position, and a message.
//!
//! A caller owns this struct and passes it to `parseFromSlice` through
//! `ParseOptions`. The parser writes into it, so the message stays valid after
//! the parse returns. On `error.SyntaxError` the fields below describe the
//! first error; on success they are untouched.

const std = @import("std");
const testing = std.testing;
const compat = @import("compat.zig");

const Diagnostics = @This();

/// Byte offsets into the source. `start` is the first byte the message refers
/// to, and `end` is one past the last byte.
pub const Span = struct {
    start: u32,
    end: u32,
};

/// The bytes the parser gave up on.
span: Span,
/// The line of `span.start`, counted from one. Line feeds and carriage
/// returns each start a line.
line: u32,
/// The column of `span.start` on that line, counted from one in bytes.
column: u32,
len: u8,
buf: [127]u8,

/// The state before a parse writes into it: an empty span at the start of
/// the source, on line 1, column 1, with no message.
pub const init: Diagnostics = .{
    .span = .{ .start = 0, .end = 0 },
    .line = 1,
    .column = 1,
    .len = 0,
    .buf = undefined,
};

/// The explanation, for example "a name cannot start with `10`".
///
/// The bytes live in this struct, so the message stays valid after the parser
/// that made it is gone.
pub fn message(self: *const Diagnostics) []const u8 {
    return self.buf[0..self.len];
}

/// Render a message into the diagnostic, truncating on a character boundary
/// when it does not fit.
pub fn setMessage(self: *Diagnostics, comptime fmt: []const u8, args: anytype) void {
    const text = compat.bufPrint(&self.buf, fmt, args) catch {
        // `bufPrint` leaves a partial message on overflow. Cut it back to a
        // UTF-8 boundary so the caller can print it without mojibake.
        var n: usize = self.buf.len;
        while (n > 0 and (self.buf[n - 1] & 0xC0) == 0x80) n -= 1;
        if (n > 0) n -= 1;
        self.len = @intCast(n);
        return;
    };
    self.len = @intCast(text.len);
}

test "message truncates on a character boundary" {
    var d: Diagnostics = .init;
    d.setMessage("é{s}", .{compat.repeatString("é", 100)});
    const text = d.message();
    try testing.expect(text.len < 127);
    try testing.expect(std.unicode.utf8ValidateSlice(text));
}

test "message keeps short text whole" {
    var d: Diagnostics = .init;
    d.setMessage("a name cannot start with `{s}`", .{"1"});
    try testing.expectEqualStrings("a name cannot start with `1`", d.message());
}
