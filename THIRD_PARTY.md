# Third-party code and data

json5 is MIT (`LICENSE`). No upstream code is adapted: the parser, the value
mapping, and the writer are written for this repository. The specification
defines what that code must do, and the conformance corpus ships here as test
data.

## JSON5

- Upstream: <https://github.com/json5/json5>
- Specification: <https://spec.json5.org>, version 1.0.0, March 2018
- License: MIT

The prose and the grammar are the reference for `src/Parser.zig` and
`src/Stringify.zig`. No text or code is copied into this repository, so
nothing from it ships in a release.

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
