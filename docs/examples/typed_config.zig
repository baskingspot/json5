const std = @import("std");
const json5 = @import("json5");

const Config = struct {
    name: []const u8,
    retry: ?u32 = null,
    tags: []const []const u8,
};

test "read a config into a struct" {
    const source =
        \\{
        \\    name: 'gateway',
        \\    failover: true,
        \\    tags: ['edge', 'internal'],
        \\}
    ;

    var config = try json5.parseFromSlice(Config, std.testing.allocator, source, .{
        // `failover` is not a field of Config, and the document is allowed to
        // carry it.
        .diagnostics = null,
        .json = .{ .ignore_unknown_fields = true },
    });
    defer config.deinit();

    try std.testing.expectEqualStrings("gateway", config.value.name);
    try std.testing.expectEqual(@as(?u32, null), config.value.retry);
    try std.testing.expectEqual(@as(usize, 2), config.value.tags.len);
    try std.testing.expectEqualStrings("internal", config.value.tags[1]);
}
