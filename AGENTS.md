# AGENTS.md

Working notes for AI coding agents in baskingspot/json5.

## What this is

JSON5 in Zig: unquoted keys, single quotes, hex numbers, NaN, and comments. It has no tagged release: the API can move until the first tag.

## Environment

Zig 0.16 and 0.17. The flake is the tool contract, from `baskingspot/nix`: `nix develop` is the current stable, Zig 0.17, and `nix develop .#zig-old` is Zig 0.16. Both provide `ziglint` and the base tools, and nothing comes from the system PATH. The justfile is the command interface: `just test`, `just check`, `just lint`, `just ci`. CI runs `just ci` on the default shell and `just check` on `zig-old`. Run `just fmt` before you commit.

The guide is `docs/content/_index.md` on the baskingspot docs theme. `just doc` builds the site into `zig-out/site/json5/`, `just guide` serves it with live reload, and the API reference comes from docgen over `src/root.zig`. The guide's code blocks are files in `docs/examples/`, embedded with `load_data` and compiled by `just test`, so a block in the guide cannot drift from code that builds. Add an example there, not inline.

The conformance corpus in `test/json5-tests/` is vendored from
`json5/json5-tests` and must not be edited to make a test pass;
`THIRD_PARTY.md` records the commit. `just test` runs the corpus.

`src/Stringify.zig` is adapted from Zig's `std/json/Stringify.zig` and is
exempt from ziglint; `THIRD_PARTY.md` records the changes and `LICENSE-ZIG`
carries the terms.

Version shims live in `src/compat.zig`. Do not write `@intFromEnum`,
`@enumFromInt`, or `**` outside it: 0.17's `zig fmt` migrates the first two,
and 0.17 removed the third. The `// zig fmt: off` block is what keeps a 0.17
format from breaking the 0.16 build.

## Rules

- Lint with `ziglint-0-16`, not `ziglint`: the wrapper points ziglint at the 0.16 std, so 0.17-only deprecations do not fire while 0.16 is supported.
- Commit messages are one line, `area: summary`, and every commit is signed. Do not rewrite pushed history.
- Gate commands on their exit codes, and claim only what you ran.
- Format with `zig fmt` and lint with `ziglint`. `just fmt` and `just lint` run both.
- This repo's GitHub settings come from `baskingspot/.github`, with `just settings`. Do not change them by hand.
- To graduate the project, follow the `baskingspot-new-repo` skill: logos, a real README, and the audit passing.

## Changelog

`CHANGELOG.md` is one file, Keep a Changelog format, newest first. Add a bullet
under `## [Unreleased]` in the same change that alters something a user can
notice: the public API, expected behavior, performance a benchmark row would
show, a supported backend, or the build requirements. Docs, CI, and internal
refactors do not need one unless they change how someone uses the package.

Write from the user's side: what changed, and what they must do about it. Name
the symbol, flag, or error. One line, under Added, Changed, Fixed, or Removed.

To release, dispatch the repo's `release.yml` with the version. The workflow
moves the Unreleased section into a dated heading, sets `.version` in
`build.zig.zon`, commits, tags, and opens the GitHub release. Do not tag by hand.
