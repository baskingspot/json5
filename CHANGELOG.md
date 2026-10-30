# Changelog

All notable changes to json5 are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `parseFromSlice` and `parseFromSliceLeaky` take the destination type first: `parseFromSlice(MyStruct, gpa, source, .{})` decodes through `std.json.parseFromValue`, and `ParseOptions.json` carries std's options.
- `Stringify.value` accepts the types `std.json.Stringify.value` accepts, including tagged unions, enums, optionals, slices, and types with a `jsonStringify` method.
- Unquoted names follow ECMAScript 5.1's IdentifierName exactly, from tables generated from Unicode 18.0.0. A `\uXXXX` escape or a surrogate pair decodes before the category check.

### Changed

- The tree form is `parseFromSlice(std.json.Value, gpa, source, .{})`; the call without a type no longer compiles.
- A name such as `☃`, `😀`, or a leading digit is `error.SyntaxError`; the earlier parser accepted any non-ASCII character.
- `Stringify.Options` gains std's `emit_null_optional_fields`, `emit_strings_as_arrays`, and `emit_nonportable_numbers_as_strings`, and keeps `allow_nonfinite`.
