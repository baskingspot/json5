# json5

JSON5 in Zig: unquoted keys, single quotes, hex numbers, NaN, and comments.

Zig has no JSON5 parser in std. This one reads a JSON5 document into the
`std.json.Value` tree you already walk, so a tree moves between this parser and
`std.json` without a conversion. `Stringify.value` writes that tree back as
strict JSON.

It reads the syntax JSON leaves out: `//` and `/* */` comments, a trailing
comma, single-quoted and multi-line strings, unquoted names, `0x` numbers, a
leading `+`, a leading or trailing decimal point, `NaN`, and `Infinity`.

```zig
const document = try json5.parseFromSlice(gpa, source, .{});
defer document.deinit();
```

The library is incubating: pin a commit, and expect the API to move.

## What is in it

- Reading a document: `parseFromSlice` returns a `Parsed`, and `deinit` frees the tree. A broken document is `error.SyntaxError`, and `Diagnostics` gives the span, line, column, and message.
- The value tree: `Value` is `std.json.Value`, so `ObjectMap` and `Array` are the map and list `std.json` builds, and member order is document order. A repeated name keeps its first position and its last value.
- Writing a value: `Stringify.value` emits strict JSON. `Options.whitespace` indents, `Options.escape_unicode` keeps the output ASCII, and `Options.allow_nonfinite = false` turns `NaN` and `Infinity` into `error.NonFiniteFloat`.
- Conformance: 114 cases from `json5-tests`, run by `just test`. Every `.json` case parses and 25 of the 26 match the `std.json` tree; every `.json5` case parses; every `.js` and `.txt` case is rejected with a diagnostic.
  Not implemented:

- Typed decoding and encoding: `parseFromSlice` returns a `Value` tree. Read fields with `Value.object.get`, and build the tree by hand.
- Streaming: the parser wants the whole document in memory.
- Comment and whitespace preservation: `Value` has no place for either, so the writer emits a normalized document.
- The full Unicode name grammar: an unquoted name accepts any non-ASCII character, not only the Unicode letter, combining mark, digit, and connector-punctuation categories.

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

## Documentation

- The doc comments in `src/` state the contract for every public symbol.
- The [JSON5 specification](https://spec.json5.org) is the grammar the parser implements.
- [`test/corpus.zig`](test/corpus.zig) shows what `just test` checks for each corpus extension.
- [`AGENTS.md`](AGENTS.md) has the working notes for the repository.

## Work on it

```sh
just ci
```

`nix develop` provides the toolchain. `just` lists the recipes, and `just ci`
runs what CI runs: the unit tests, the vendored `json5-tests` corpus, and lint.

## License

MIT. See [`LICENSE`](LICENSE). The conformance corpus is vendored from
[`json5/json5-tests`](https://github.com/json5/json5-tests);
[`THIRD_PARTY.md`](THIRD_PARTY.md) lists its terms.

## How it's made

Built with LLM assistance. [How, in detail](https://github.com/baskingspot/.github/blob/main/docs/AI.md).

<a href="https://github.com/baskingspot"><img src="https://raw.githubusercontent.com/baskingspot/.github/main/brand/assets/badge.svg" alt="baskingspot" height="24"></a>
