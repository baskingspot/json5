+++
title = "json5"
+++

JSON5 in Zig: unquoted keys, single quotes, hex numbers, NaN, and comments.

Zig has no JSON5 parser in std. This one reads a JSON5 document into the
`std.json.Value` tree you already walk, so a tree moves between this parser and
`std.json` without a conversion. `parseFromSlice` takes a destination type when
you want one, and `Stringify.value` writes the tree, or any type `std.json`
knows, back as strict JSON.

- [Reading a value](#reading-a-value): `parseFromSlice(std.json.Value, ...)` returns a `Parsed`, and `Diagnostics` gives the span, line, and message of the first syntax error.
- [Typed reading](#typed-reading): pass a struct, union, enum, or slice as the first argument, and `std.json.parseFromValue` builds it. `ParseOptions.json` holds std's options.
- [Writing](#writing): `Stringify.value` takes the types `std.json.Stringify.value` takes, and `Options` sets indentation, ASCII escaping, and what happens to `NaN`.
- [Identifiers](#identifiers): a name is ASCII IdentifierStart and IdentifierPart plus any non-ASCII code point, and a `\uXXXX` escape or a surrogate pair decodes first.
- [Conformance](#conformance): 114 cases from `json5-tests`, run by `just test`.
- [Limits](#limits): a parser that wants the whole source and a writer that normalizes the document.

The doc comments in `src/` state the contract for every public symbol.

# Getting started

## Install

```sh
zig fetch --save git+https://github.com/baskingspot/json5
```

Add the module in `build.zig`:

```zig
const json5 = b.dependency("json5", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("json5", json5.module("json5"));
```

`json5` builds with Zig 0.16 only.

## Import it

```zig
const json5 = @import("json5");
```

`std.json` keeps its name, so `json5` and `std.json` can share a file.

## Read the examples

The tests in `src/` use every symbol this page names, and `just test` runs them
with the corpus.

# Reading a value

## Parse one document

```zig
const document = try json5.parseFromSlice(std.json.Value, gpa, source, .{});
defer document.deinit();

const root = document.value;
```

`parseFromSlice` copies every string, object, and array into an arena that the
`Parsed` owns, so the source may be freed as soon as it returns.
`document.deinit()` frees the arena.

A document that breaks the grammar is `error.SyntaxError`. Pass a
`Diagnostics` and it holds the span, line, byte column, and message of the
first error:

```zig
var diagnostics: json5.Diagnostics = undefined;
const document = try json5.parseFromSlice(std.json.Value, gpa, source, .{
    .diagnostics = &diagnostics,
});
```

The diagnostics are untouched when the parse succeeds and on
`error.OutOfMemory`.

## Walk the tree

`Value` is `std.json.Value`, so the tags are the ones std uses: `.null`,
`.bool`, `.integer`, `.float`, `.string`, `.array`, and `.object`. An object
is a `std.json.ObjectMap` and an array is a `std.json.Array`.

```zig
const name = document.value.object.get("name") orelse return error.NoName;
std.debug.print("{s}\n", .{name.string});
```

Member order is document order. A repeated name keeps its first position and
its last value, which is what a JavaScript object does.

A number literal with no fraction and no exponent is `.integer` when it fits
`i64`. Every other number is `.float`, including a hexadecimal value past
`i64` and `-0`. `.number_string` is never set.

# Typed reading

## Parse into a struct

The first argument is the destination type:

```zig
const Config = struct {
    name: []const u8,
    retry: ?u32 = null,
};

var config = try json5.parseFromSlice(Config, gpa, source, .{});
defer config.deinit();
```

The parser builds a `std.json.Value` tree, then `std.json.parseFromValue`
turns that tree into `Config`. `T` can be anything std accepts: a struct, a
tagged union, an enum, an optional, a slice, or a type with its own
`jsonParseFromValue`. When `T` is `std.json.Value`, the second pass is
skipped.

`ParseOptions.json` is a `std.json.ParseOptions`, used for the second pass:

```zig
var config = try json5.parseFromSlice(Config, gpa, source, .{
    .json = .{ .ignore_unknown_fields = true },
});
```

The defaults are std's: an unknown field is `error.UnknownField`, a repeated
field is `error.DuplicateField`, and a field with a default value may be
missing.

## What std.json accepts

The mapping is std's `parseFromValue`: struct fields by name, tagged unions as
an object with the tag as its key, enums by tag name or integer, optionals as
`null` or the payload, and slices as arrays. A type that declares

```zig
pub fn jsonParseFromValue(
    allocator: std.mem.Allocator,
    source: std.json.Value,
    options: std.json.ParseOptions,
) !@This()
```

is decoded by that method instead.

`parseFromSliceLeaky(T, arena.allocator(), source, .{})` is the same parse
into an arena the caller owns. The arena must stay at the same address while the value
lives, because a `std.json.Value` tree's arrays hold the allocator built from
it.

# Writing

## Write a value

```zig
var output: std.Io.Writer.Allocating = .init(gpa);
defer output.deinit();
try json5.Stringify.value(document.value, .{ .whitespace = .indent_2 }, &output.writer);
```

`Stringify.value` takes the types `std.json.Stringify.value` takes: null,
bool, integers, floats, enums, tagged unions, optionals, arrays, slices,
vectors, structs, tuples, and any type with a `jsonStringify` method. The
output is strict JSON. `Options` sets `whitespace`, `escape_unicode`,
`allow_nonfinite`, and std's `emit_*` options.

## Non-finite floats

JSON cannot spell `NaN` or `Infinity`, so the writer emits the JSON5 form:
`NaN`, `Infinity`, or `-Infinity`. With `allow_nonfinite = false`, a
non-finite float is `error.NonFiniteFloat`.

A finite float that is integral is written with a trailing `.0`, as in `1.0`,
so it reads back as a float. The trailing `.0` and the spelling of a
non-finite value are the two places the output differs from `std.json`.

## The jsonStringify protocol

```zig
const Release = struct {
    major: u16,
    minor: u16,

    pub fn jsonStringify(self: Release, jws: anytype) !void {
        try jws.print("\"{d}.{d}\"", .{ self.major, self.minor });
    }
};
```

The writer's methods are `beginObject`, `endObject`, `objectField`,
`objectFieldRaw`, `beginObjectFieldRaw`, `endObjectFieldRaw`, `beginArray`,
`endArray`, `write`, `print`, `beginWriteRaw`, and `endWriteRaw`.
`std.json.Value` uses the same protocol, which is how the tree is written.

# Identifiers

## The ASCII subset

IdentifierStart is `$`, `_`, or an ASCII letter. IdentifierPart adds the
digits. Any non-ASCII code point is accepted in either position as well, which
is wider than ES5.1. `Ümläüt`, `aδ`, `$x`, and `_` are names, and so is `☃`.
A leading digit is a syntax error. `# Limits` states what the wider rule
costs.

## Escapes

A `\uXXXX` in a name is decoded before the name rule is applied. A high surrogate
must be followed by a low surrogate, and the pair decodes to one code point,
so `\uD801\uDC00` is U+10400 and can start a name. A lone surrogate is a
syntax error.

# Conformance

## The corpus

`test/json5-tests/` vendors `json5-tests` at commit `ceb24d4`: 26 `.json`
documents, 57 `.json5` documents, 6 `.js` files, and 25 `.txt` files.
`just test` runs all 114.

## What the runner checks

Every `.json` case parses, and every one with a `std.json` tree matches it.
The exception is `comments/irregular-block-comment.json`, an upstream file
with the wrong extension that holds a block comment. Every `.json5` case
parses and round-trips through the writer. Every `.js` and `.txt` case fails
with `error.SyntaxError` and a diagnostic inside the source.

# Limits

- The parser wants the whole source in memory. There is no streaming entry point.
- `Value` has no place for comments or extra whitespace, so the writer emits a normalized document.
- A map without a `jsonStringify` method is written as a struct of its fields, because that is what `std.json.Stringify` does.
- The exact ES5.1 identifier categories: a name accepts ASCII plus any non-ASCII code point, and the categories would need a Unicode property table this package does not vendor.
- Objects and arrays may nest 256 deep. The parser returns `error.SyntaxError` past that, and the writer returns `error.NestingTooDeep`.
