<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/static/logo-dark.svg">
    <img src="docs/static/logo.svg" alt="json5" height="48">
  </picture>
</h1>

JSON5 in Zig: unquoted keys, single quotes, hex numbers, NaN, and comments.

Zig has no JSON5 parser in std. This one reads a JSON5 document into the
`std.json.Value` tree you already walk, so a tree moves between this parser and
`std.json` without a conversion. Pass a type to `parseFromSlice` when you want
one, and `Stringify.value` writes the tree or any type `std.json` knows back as
strict JSON.

It reads the syntax JSON leaves out: `//` and `/* */` comments, a trailing
comma, single-quoted and multi-line strings, unquoted names, `0x` numbers, a
leading `+`, a leading or trailing decimal point, `NaN`, and `Infinity`.

```zig
const document = try json5.parseFromSlice(std.json.Value, gpa, source, .init);
defer document.deinit();
```

The API is pre-1.0: pin the commit, and expect it to move.

## What is in it

- [Reading a value](https://baskingspot.dev/json5/#reading-a-value): `parseFromSlice` returns a `Parsed`, and `Diagnostics` gives the span, line, column, and message of the first syntax error.
- [Typed reading](https://baskingspot.dev/json5/#typed-reading): the first argument is the destination type, `std.json.parseFromValue` builds it, and `ParseOptions.json` carries std's options.
- [Writing](https://baskingspot.dev/json5/#writing): `Stringify.value` emits strict JSON for the tree or any type std knows, with indentation, ASCII escaping, and `NaN` handling in `Options`.
- [Identifiers](https://baskingspot.dev/json5/#identifiers): a name is ASCII IdentifierStart and IdentifierPart plus any non-ASCII code point, and a `\uXXXX` escape or a surrogate pair decodes first.
- [Conformance](https://baskingspot.dev/json5/#conformance): 114 cases from `json5-tests`, run by `just test`. Every `.json` case parses and 25 of the 26 match the `std.json` tree; every `.json5` case parses; every `.js` and `.txt` case is rejected with a diagnostic.
- [Limits](https://baskingspot.dev/json5/#limits): a parser that wants the whole source and a writer that normalizes the document.

Not implemented:

- Streaming: `parseFromSlice` wants the whole document in memory.
- Comment and whitespace preservation: `Value` has no place for either, so the writer emits a normalized document.
- A map arm: a map without a `jsonStringify` method is written as a struct of its fields, as in `std.json`.
- The exact ES5.1 identifier categories: a name accepts ASCII plus any non-ASCII code point, and the categories would need a Unicode property table this package does not vendor.
- 256-deep nesting: the parser returns `error.SyntaxError` past that, and the writer returns `error.NestingTooDeep`.

## Install

```sh
zig fetch --save https://baskingspot.dev/json5/v0.1.0.tar.gz
```

Add the module in `build.zig`:

```zig
const json5 = b.dependency("json5", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("json5", json5.module("json5"));
```

`std.json` keeps its name, so `json5` can sit beside it in the same file. `json5` builds with Zig 0.16 only.

## Documentation

- The [guide](https://baskingspot.dev/json5/) covers reading, typed reading, writing, identifiers, and the corpus.
- The [API reference](https://baskingspot.dev/json5/api/) documents every public symbol in `src/root.zig`.
- [`docs/examples/`](docs/examples/) is the test-verified code shown in the guide: `just test` compiles and runs it alongside the module's own tests.
- [`AGENTS.md`](AGENTS.md) has the working notes for the repository.

## Work on it

```sh
just ci
```

`nix develop` provides the toolchain and the site tools. `just` lists the recipes, and `just ci` runs what CI runs: the unit tests, the `json5-tests` corpus, lint, and the site build. `just guide` serves the guide with live reload, and `just doc` builds the whole site into `zig-out/site/json5/`.

The corpus is the vendored `test/json5-tests/` tree; `test/corpus.zig` says what each extension must do. `just test` runs it with the unit tests.

## License

MIT. See [`LICENSE`](LICENSE). `src/Stringify.zig` is adapted from Zig's standard library; [`THIRD_PARTY.md`](THIRD_PARTY.md) lists its terms and [`LICENSE-ZIG`](LICENSE-ZIG) reproduces them. The conformance corpus is vendored from [`json5/json5-tests`](https://github.com/json5/json5-tests); [`THIRD_PARTY.md`](THIRD_PARTY.md) lists its terms. The logo files in `docs/static/` are baskingspot marks and are not covered by it. See [`docs/static/LICENSE`](docs/static/LICENSE).

## How it's made

Built with LLM assistance. [How, in detail](https://github.com/baskingspot/.github/blob/main/docs/AI.md).

<a href="https://github.com/baskingspot"><img src="https://raw.githubusercontent.com/baskingspot/.github/main/brand/assets/badge.svg" alt="baskingspot" height="24"></a>
