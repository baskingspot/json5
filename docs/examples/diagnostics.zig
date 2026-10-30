const std = @import("std");
const json5 = @import("json5");

test "a bad document comes back with its position" {
    const source = "{\n    name: 'gateway',\n    port: ,\n}";

    var diagnostics: json5.Diagnostics = undefined;
    try std.testing.expectError(error.SyntaxError, json5.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        source,
        .{ .diagnostics = &diagnostics },
    ));

    try std.testing.expectEqual(@as(u32, 3), diagnostics.line);
    try std.testing.expectEqual(@as(u32, 11), diagnostics.column);
    try std.testing.expectEqualStrings("expected a value", diagnostics.message());
}
