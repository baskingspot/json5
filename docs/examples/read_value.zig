const std = @import("std");
const json5 = @import("json5");

const source =
    \\// The vhost entry.
    \\{
    \\    name: 'gateway',
    \\    port: 8080,
    \\    routes: ['/api', '/health',],
    \\    debug: false,
    \\}
;

test "parse a document into the std.json tree" {
    var document = try json5.parseFromSlice(std.json.Value, std.testing.allocator, source, .init);
    defer document.deinit();

    const root = document.value.object;
    try std.testing.expectEqualStrings("gateway", root.get("name").?.string);
    try std.testing.expectEqual(@as(i64, 8080), root.get("port").?.integer);
    try std.testing.expectEqual(false, root.get("debug").?.bool);

    const routes = root.get("routes").?.array;
    try std.testing.expectEqual(@as(usize, 2), routes.items.len);
    try std.testing.expectEqualStrings("/health", routes.items[1].string);
}

test "a repeated name keeps its first position and its last value" {
    var document = try json5.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "{ a: 1, b: 2, a: 3 }",
        .init,
    );
    defer document.deinit();

    const root = document.value.object;
    try std.testing.expectEqual(@as(usize, 2), root.count());
    try std.testing.expectEqual(@as(i64, 3), root.get("a").?.integer);
}
