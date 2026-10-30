# json5: JSON5 in Zig: unquoted keys, single quotes, hex numbers, NaN, and comments. `just --list` shows the recipes.
# AGENTS.md holds the working conventions.

[private]
default:
    @just --list

[doc("Unit tests: the module and the json5-tests corpus, one line per test binary via testingx")]
[group("test")]
test:
    zig build test --summary all

[doc("Lint Zig, Nix, Markdown, the workflows, and this justfile: ziglint, zig fmt, nix fmt, oxfmt, actionlint, zizmor, and just --fmt")]
[group("lint")]
lint:
    ziglint
    zig fmt --check src test/corpus.zig build.zig build.zig.zon
    nix fmt -- --ci
    oxfmt --check README.md AGENTS.md CHANGELOG.md THIRD_PARTY.md docs/content .github .oxfmtrc.jsonc
    actionlint
    zizmor .
    just --fmt --check

[doc("Format everything lint checks")]
[group("lint")]
fmt:
    zig fmt src test/corpus.zig build.zig build.zig.zon
    nix fmt
    oxfmt README.md AGENTS.md CHANGELOG.md THIRD_PARTY.md docs/content .github .oxfmtrc.jsonc
    just --fmt

[doc("Everything CI runs: the tests and lint")]
[group("ci")]
ci: test lint
