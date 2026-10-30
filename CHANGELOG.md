# Changelog

All notable changes to json5 are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `parseFromSlice` and `parseFromSliceLeaky` take the destination type first: `parseFromSlice(MyStruct, gpa, source, .{})` decodes through `std.json.parseFromValue`, and `ParseOptions.json` carries std's options.
- `Stringify.value` accepts the types `std.json.Stringify.value` accepts, including tagged unions, enums, optionals, slices, and types with a `jsonStringify` method.

### Changed

- `ParseOptions`, `Diagnostics`, `Stringify.Options`, and `Stringify` now require every field: use `ParseOptions.init` or `Diagnostics.init` for the defaults, spell all of `Stringify.Options` for a custom value, and build a writer with `Stringify.init(writer, options)` instead of a struct literal.
- The tree form is `parseFromSlice(std.json.Value, gpa, source, .init)`; the call without a type no longer compiles.
- `Stringify.Options` gains std's `emit_null_optional_fields`, `emit_strings_as_arrays`, and `emit_nonportable_numbers_as_strings`, and keeps `allow_nonfinite`.
