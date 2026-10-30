const std = @import("std");
const json5 = @import("json5");

const Release = struct {
    major: u16,
    minor: u16,

    pub fn jsonStringify(self: Release, jws: anytype) !void {
        try jws.print("\"{d}.{d}\"", .{ self.major, self.minor });
    }
};

test "a type with jsonStringify decides its own form" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try json5.Stringify.value(Release{ .major = 0, .minor = 2 }, .init, &output.writer);

    try std.testing.expectEqualStrings("\"0.2\"", output.written());
}
