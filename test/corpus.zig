//! The json5-tests conformance corpus, run against the public API.
//!
//! `test/json5-tests/` holds github.com/json5/json5-tests at the commit named
//! in `THIRD_PARTY.md`, vendored as data. The extension decides the contract:
//! every `.json` case parses, every `.json` case with a `std.json` tree matches
//! it, every `.json5` case parses, and every `.js` and `.txt` case is rejected
//! with a diagnostic.
//!
//! The tests read the corpus from the build root, so `build.zig` sets the test
//! runner's working directory. A consumer that runs the tests from somewhere
//! else gets a clear file-not-found instead of a false pass.

const std = @import("std");
const testing = std.testing;
const json5 = @import("json5");

const corpus = "test/json5-tests";
const max_file_size = 16 * 1024 * 1024;
const max_failures = 10;

/// `.json` cases that hold a JSON5 form, so `std.json` rejects them. The
/// corpus README says a `.json` case is strict JSON, and this one does not
/// follow it: it was added on 2026-02-19 with a block comment after the value.
/// Our parser must still accept it, and there is no `std.json` tree to match.
const json5_only = [_][]const u8{"comments/irregular-block-comment.json"};

const Kind = enum { json, json5, rejected };

const Case = struct {
    path: []const u8,
    kind: Kind,
};

test "every .json case matches the std.json tree" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const cases = try collect(allocator);
    var checked: usize = 0;
    var failures: usize = 0;
    for (cases) |case| {
        if (case.kind != .json) continue;
        checked += 1;
        const source = try readFile(allocator, case.path);
        // `std.json` rejects a repeated name by default; a JavaScript object
        // keeps the last value, which is what JSON5 means.
        const expected: ?std.json.Value = std.json.parseFromSliceLeaky(
            std.json.Value,
            allocator,
            source,
            .{ .duplicate_field_behavior = .use_last },
        ) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => if (isJson5Only(case.path)) null else {
                try report(case.path, "std.json rejected it: {s}", .{@errorName(err)});
                failures += 1;
                if (failures == max_failures) break;
                continue;
            },
        };
        var diagnostics: json5.Diagnostics = undefined;
        const actual = json5.parseFromSliceLeaky(allocator, source, .{
            .diagnostics = &diagnostics,
        }) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.SyntaxError => {
                try report(case.path, "it did not parse: {s}", .{diagnostics.message()});
                failures += 1;
                if (failures == max_failures) break;
                continue;
            },
        };
        if (expected) |tree| {
            expectSame(case.path, "", &tree, actual) catch {
                failures += 1;
                if (failures == max_failures) break;
            };
        }
    }
    try testing.expect(checked > 0);
    if (failures != 0) return error.CorpusMismatch;
}

test "every .json5 case parses and survives the writer" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const cases = try collect(allocator);
    var checked: usize = 0;
    var failures: usize = 0;
    for (cases) |case| {
        if (case.kind != .json5) continue;
        checked += 1;
        const source = try readFile(allocator, case.path);
        var diagnostics: json5.Diagnostics = undefined;
        const first = json5.parseFromSliceLeaky(allocator, source, .{
            .diagnostics = &diagnostics,
        }) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.SyntaxError => {
                try report(case.path, "it did not parse: {s}", .{diagnostics.message()});
                failures += 1;
                if (failures == max_failures) break;
                continue;
            },
        };

        var output: std.Io.Writer.Allocating = .init(allocator);
        json5.Stringify.value(first, .{}, &output.writer) catch |err| {
            try report(case.path, "writing it failed: {s}", .{@errorName(err)});
            failures += 1;
            if (failures == max_failures) break;
            continue;
        };
        const second = json5.parseFromSliceLeaky(allocator, output.written(), .{
            .diagnostics = &diagnostics,
        }) catch |err| switch (err) {
            error.OutOfMemory => return err,
            error.SyntaxError => {
                try report(case.path, "the written value does not parse: {s}", .{
                    diagnostics.message(),
                });
                failures += 1;
                if (failures == max_failures) break;
                continue;
            },
        };
        if (!sameValue(first, second)) {
            try report(case.path, "the written value reads back as another tree", .{});
            failures += 1;
            if (failures == max_failures) break;
        }
    }
    try testing.expect(checked > 0);
    if (failures != 0) return error.CorpusMismatch;
}

test "every .js and .txt case is rejected with a diagnostic" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const cases = try collect(allocator);
    var checked: usize = 0;
    var failures: usize = 0;
    for (cases) |case| {
        if (case.kind != .rejected) continue;
        checked += 1;
        const source = try readFile(allocator, case.path);
        var diagnostics: json5.Diagnostics = undefined;
        const result = json5.parseFromSliceLeaky(allocator, source, .{
            .diagnostics = &diagnostics,
        });
        if (result) |_| {
            try report(case.path, "it parsed, and it must not", .{});
            failures += 1;
        } else |err| switch (err) {
            error.OutOfMemory => return err,
            error.SyntaxError => {
                if (diagnostics.message().len == 0) {
                    try report(case.path, "the diagnostics have no message", .{});
                    failures += 1;
                } else if (diagnostics.line == 0 or diagnostics.column == 0) {
                    try report(case.path, "the diagnostics have no position", .{});
                    failures += 1;
                } else if (diagnostics.span.end < diagnostics.span.start) {
                    try report(case.path, "the diagnostics span is reversed", .{});
                    failures += 1;
                } else if (diagnostics.span.end > source.len) {
                    try report(case.path, "the diagnostics span runs off the source", .{});
                    failures += 1;
                }
            },
        }
        if (failures == max_failures) break;
    }
    try testing.expect(checked > 0);
    if (failures != 0) return error.CorpusMismatch;
}

// Corpus access

fn collect(allocator: std.mem.Allocator) ![]Case {
    const io = testing.io;
    var dir = try std.Io.Dir.cwd().openDir(io, corpus, .{ .iterate = true });
    defer dir.close(io);

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    var cases: std.ArrayList(Case) = .empty;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const kind: Kind = if (std.mem.endsWith(u8, entry.path, ".json"))
            .json
        else if (std.mem.endsWith(u8, entry.path, ".json5"))
            .json5
        else if (std.mem.endsWith(u8, entry.path, ".js") or std.mem.endsWith(u8, entry.path, ".txt"))
            .rejected
        else
            continue;
        try cases.append(allocator, .{
            .path = try allocator.dupe(u8, entry.path),
            .kind = kind,
        });
    }
    return cases.toOwnedSlice(allocator);
}

fn isJson5Only(path: []const u8) bool {
    for (json5_only) |known| {
        if (std.mem.eql(u8, path, known)) return true;
    }
    return false;
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const full = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ corpus, path });
    return std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        full,
        allocator,
        .limited(max_file_size),
    );
}

fn report(path: []const u8, comptime fmt: []const u8, args: anytype) error{CorpusMismatch}!void {
    std.debug.print("{s}: ", .{path});
    std.debug.print(fmt ++ "\n", args);
    return error.CorpusMismatch;
}

// Comparison against std.json

fn expectSame(
    path: []const u8,
    key: []const u8,
    expected: *const std.json.Value,
    actual: std.json.Value,
) error{CorpusMismatch}!void {
    switch (expected.*) {
        .null => if (actual != .null) return mismatch(path, key, actual, "null"),
        .bool => |wanted| if (actual != .bool or actual.bool != wanted) {
            return mismatch(path, key, actual, "a boolean");
        },
        .integer => |wanted| if (actual != .integer or actual.integer != wanted) {
            return mismatch(path, key, actual, "an integer");
        },
        .float => |wanted| {
            if (actual != .float) return mismatch(path, key, actual, "a float");
            const found = actual.float;
            const same = if (std.math.isNan(wanted)) std.math.isNan(found) else wanted == found;
            if (!same) {
                return report(path, "{s}: expected {d}, found {d}", .{ key, wanted, found });
            }
        },
        .number_string => |wanted| {
            // Our parser never writes `.number_string`; an integer past i64
            // arrives as a float. Compare the value they name.
            const number = std.fmt.parseFloat(f64, wanted) catch {
                return report(path, "{s}: the expectation's number is malformed", .{key});
            };
            if (actual != .float or actual.float != number) {
                return mismatch(path, key, actual, "a number");
            }
        },
        .string => |wanted| {
            if (actual != .string or !std.mem.eql(u8, actual.string, wanted)) {
                return mismatch(path, key, actual, "a string");
            }
        },
        .array => |wanted| {
            if (actual != .array) return mismatch(path, key, actual, "an array");
            if (actual.array.items.len != wanted.items.len) {
                return report(path, "{s}: expected {d} elements, found {d}", .{
                    key,
                    wanted.items.len,
                    actual.array.items.len,
                });
            }
            for (wanted.items, actual.array.items) |want, found| {
                try expectSame(path, key, &want, found);
            }
        },
        .object => |wanted| {
            if (actual != .object) return mismatch(path, key, actual, "an object");
            if (actual.object.count() != wanted.count()) {
                return report(path, "{s}: expected {d} keys, found {d}", .{
                    key,
                    wanted.count(),
                    actual.object.count(),
                });
            }
            var it = wanted.iterator();
            while (it.next()) |entry| {
                const found = actual.object.get(entry.key_ptr.*) orelse {
                    return report(path, "{s}: the key `{s}` is missing", .{ key, entry.key_ptr.* });
                };
                try expectSame(path, entry.key_ptr.*, entry.value_ptr, found);
            }
        },
    }
}

fn mismatch(
    path: []const u8,
    key: []const u8,
    actual: std.json.Value,
    wanted: []const u8,
) error{CorpusMismatch}!void {
    return report(path, "{s}: expected {s}, found a {s}", .{ key, wanted, @tagName(actual) });
}

fn sameValue(a: std.json.Value, b: std.json.Value) bool {
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
