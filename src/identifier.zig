//! ECMAScript 5.1's IdentifierName, backed by the generated Unicode ranges.
//!
//! IdentifierStart is `$`, `_`, or a letter in the Lu, Ll, Lt, Lm, Lo, or Nl
//! category. IdentifierPart is IdentifierStart plus Mn, Mc, Nd, Pc, and the
//! two zero-width joiners. `identifier_ranges.zig` holds the ranges, generated
//! from Unicode 18.0.0.

const std = @import("std");
const testing = std.testing;
const ranges = @import("identifier_ranges.zig");

/// Can `cp` start a name?
pub fn isStart(cp: u21) bool {
    if (cp < 0x80) {
        return switch (cp) {
            'A'...'Z', 'a'...'z', '$', '_' => true,
            else => false,
        };
    }
    return inRanges(ranges.start, cp);
}

/// Can `cp` continue a name?
pub fn isPart(cp: u21) bool {
    if (cp < 0x80) {
        return switch (cp) {
            'A'...'Z', 'a'...'z', '0'...'9', '$', '_' => true,
            else => false,
        };
    }
    return inRanges(ranges.part, cp);
}

fn inRanges(table: []const ranges.Range, cp: u21) bool {
    var low: usize = 0;
    var high: usize = table.len;
    while (low < high) {
        const mid = low + (high - low) / 2;
        if (cp < table[mid].first) {
            high = mid;
        } else if (cp > table[mid].last) {
            low = mid + 1;
        } else {
            return true;
        }
    }
    return false;
}

test "IdentifierStart" {
    const accepted = [_]u21{
        '$', '_', 'A', 'z',
        0x00DC, // Ü, Ll
        0x03B4, // δ, Ll
        0x03A3, // Σ, Lu
        0x10400, // Deseret capital letter long i, Lu, outside the BMP
    };
    for (accepted) |cp| try testing.expect(isStart(cp));

    const rejected = [_]u21{
        '0', '9',
        0x20, // space
        0x0301, // combining acute accent, Mn: a part, not a start
        0x203F, // undertie, Pc: a part, not a start
        0x200C, // ZWNJ: a part, not a start
        0x200D, // ZWJ: a part, not a start
        0x2603, // snowman, So
        0x1F600, // grinning face, So
    };
    for (rejected) |cp| try testing.expect(!isStart(cp));
}

test "IdentifierPart" {
    const accepted = [_]u21{
        '$', '_', 'A', 'z', '0', '9',
        0x0301, // combining acute accent, Mn
        0x203F, // undertie, Pc
        0x200C, // ZWNJ
        0x200D, // ZWJ
        0x10400, // Deseret capital letter long i, Lu
    };
    for (accepted) |cp| try testing.expect(isPart(cp));

    const rejected = [_]u21{
        0x20, // space
        0x2603, // snowman, So
        0x1F600, // grinning face, So
    };
    for (rejected) |cp| try testing.expect(!isPart(cp));
}
