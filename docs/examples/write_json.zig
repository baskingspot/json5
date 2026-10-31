const std = @import("std");
const json5 = @import("json5");

test "write the tree as strict JSON" {
    const source =
        \\{
        \\    name: 'gateway',
        \\    retry: 3,
        \\}
    ;

    var document = try json5.parseFromSlice(std.json.Value, std.testing.allocator, source, .{});
    defer document.deinit();

    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try json5.Stringify.value(document.value, .{
        .allow_nonfinite = true,
        .whitespace = .indent_2,
        .emit_null_optional_fields = true,
        .emit_strings_as_arrays = false,
        .escape_unicode = false,
        .emit_nonportable_numbers_as_strings = false,
    }, &output.writer);

    try std.testing.expectEqualStrings(
        \\{
        \\  "name": "gateway",
        \\  "retry": 3
        \\}
    , output.written());
}
