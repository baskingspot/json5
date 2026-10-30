# Changelog

All notable changes to json5 are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.1.0] - 2026-10-30

### Added

- `parseFromSlice(T, allocator, source, options)` reads a JSON5 document into
  any type `std.json.parseFromValue` accepts, including `std.json.Value`, which
  returns the tree with no second pass. `parseFromSliceLeaky` leaves the memory
  with the caller. A syntax error is `error.SyntaxError`, and
  `ParseOptions.diagnostics` points at a caller-owned `Diagnostics` with a byte
  span, a one-based line and column, and a message. `ParseOptions.json` carries
  `std.json`'s options for the typed pass.
- `Parsed(T)` owns the arena; `deinit` frees the tree.
- `Stringify.value` writes the types `std.json.Stringify.value` writes,
  including structs, tagged unions, enums, optionals, slices, and types with a
  `jsonStringify` method. `Stringify.Options` sets indentation, ASCII escaping,
  and whether a non-finite float is written or rejected.
- Non-finite floats are written as `NaN`, `Infinity`, and `-Infinity`, which
  JSON5 allows and strict JSON does not. `allow_nonfinite = false` returns
  `error.NonFiniteFloat` instead.
- The `json5-tests` corpus runs in `just test`: 114 cases, every `.json` tree
  compared against `std.json`, every `.json5` document parsed and written back,
  and every `.js` and `.txt` rejected with a diagnostic.
