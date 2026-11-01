# json5: JSON5 in Zig: unquoted keys, single quotes, hex numbers, NaN, and comments. `just --list` shows the recipes.
# AGENTS.md holds the working conventions.

[private]
default:
    @just --list

[doc("Unit tests: the module, the json5-tests corpus, and the guide's examples, one line per test binary via testingx")]
[group("test")]
test:
    zig build test --summary all

[doc("Lint Zig, Nix, Markdown, the workflows, and this justfile: ziglint, the ast-grep rules, zig fmt, nix fmt, oxfmt, actionlint, zizmor, and just --fmt")]
[group("lint")]
lint:
    ziglint-0-16
    baskingspot-lint src
    zig fmt --check src docs/examples test/corpus.zig build.zig build.zig.zon
    nix fmt -- --ci
    oxfmt --check README.md AGENTS.md CHANGELOG.md THIRD_PARTY.md docs/content docs/config.toml .github .oxfmtrc.jsonc
    actionlint
    zizmor .
    just --fmt --check

[doc("Format everything lint checks")]
[group("lint")]
fmt:
    zig fmt src docs/examples test/corpus.zig build.zig build.zig.zon
    nix fmt
    oxfmt README.md AGENTS.md CHANGELOG.md THIRD_PARTY.md docs/content docs/config.toml .github .oxfmtrc.jsonc
    just --fmt

[doc("The per-version gate: the module, the corpus, and the guide's examples")]
[group("ci")]
check: test

[doc("Everything CI runs: the gate, lint, and the docs build")]
[group("ci")]
ci: check lint doc

[doc("Build the site into zig-out/site/json5/: the guide (Zola, from docs/) and the API reference (docgen JSON, rendered by the theme's api.html) under api/. The router in baskingspot/site serves /json5/... from it")]
[group("docs")]
doc: api
    baskingspot-docs build json5

[doc("Edit the guide with live reload (http://127.0.0.1:1111), API reference included")]
[group("docs")]
guide: api
    baskingspot-docs serve json5

# The API reference data. docgen comes from the baskingspot flake's docs shell,
# so this is not a Zig build dependency.
[private]
api:
    docgen --root src/root.zig --title json5 --repo-url https://github.com/baskingspot/json5 --rev main --format json --out docs/data

[doc("Deploy the rendered docs to Cloudflare as an assets-only Worker (config in wrangler.jsonc). Needs CLOUDFLARE_API_TOKEN in the environment, plus CLOUDFLARE_ACCOUNT_ID if the token can see more than one account")]
[group("docs")]
doc-deploy: doc
    wrangler deploy
