# Third-party code and data

json5 is MIT (`LICENSE`). This file lists every piece adapted from code under
another license, so those terms travel with the package. The JSON5
specification defines what the code must do, and one conformance corpus ships
here as test data.

## Zig standard library

Upstream: Zig 0.16.0 `std/json/Stringify.zig`.
License: MIT, Copyright (c) Zig contributors. The full text is in
`LICENSE-ZIG`, per its terms.

`src/Stringify.zig` is adapted from that file. It keeps the writer type, the
punctuation and indentation state machine, the type dispatch, the raw-write
methods, and the file's tests. The changes:

- The `std` import, a `depth` counter that returns `error.NestingTooDeep`, and
  the `allow_nonfinite` option.
- A finite float is written by `std.fmt.float` with a trailing `.0` when the
  value is integral. A non-finite one is `NaN`, `Infinity`, or `-Infinity`.
- Two tests that expected `42` for the float `42.0` expect `42.0`.

`src/Stringify.zig` is exempt from `ziglint` for the same reason as other
vendored code. `zig fmt` still checks it. No other file in `src/` copies Zig
code.

## JSON5

- Upstream: <https://github.com/json5/json5>
- Specification: <https://spec.json5.org>, version 1.0.0, March 2018
- License: MIT

The prose and the grammar are the reference for `src/Parser.zig` and the
float and string rules in `src/Stringify.zig`. No text or code is copied into
this repository, so nothing from it ships in a release.

## json5-tests

- Upstream: <https://github.com/json5/json5-tests>
- License: MIT, in `test/json5-tests/LICENSE.md`, kept verbatim
- Pinned commit: `ceb24d4080137d70833f86c25659c1331b80a387`

`test/json5-tests/` holds the corpus, vendored as data:

- `**/*.json` holds 26 documents that must parse. 25 also match the tree
  `std.json` builds from them. `comments/irregular-block-comment.json` holds a
  block comment, so it is JSON5-only and has no `std.json` tree.
- `**/*.json5` holds 57 documents that must parse.
- `**/*.js` holds 6 documents that must fail.
- `**/*.txt` holds 25 documents that must fail.

The corpus is read by `test/corpus.zig` at test time. It is not compiled into
the library and is not listed in `build.zig.zon`'s `paths`, so a `zig fetch`
tarball does not carry it.
