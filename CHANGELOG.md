# Changelog

All notable changes to json5 are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `parseFromSlice` and `parseFromSliceLeaky` read one JSON5 value into a `std.json.Value` tree, and `Diagnostics` gives the span, line, and message of the first syntax error.
- `Stringify.value` writes a `std.json.Value` as strict JSON, with `Options.whitespace`, `Options.escape_unicode`, and `Options.allow_nonfinite`; `NaN`, `Infinity`, and `-Infinity` are written only because JSON cannot.
