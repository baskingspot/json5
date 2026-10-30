//! Every example the guide embeds. Each file is a complete program
//! that `zig build test` compiles and runs, so a guide page cannot
//! show code that does not build.

const std = @import("std");

pub const read_value = @import("read_value.zig");
pub const diagnostics = @import("diagnostics.zig");
pub const typed_config = @import("typed_config.zig");
pub const write_json = @import("write_json.zig");
pub const write_protocol = @import("write_protocol.zig");

test {
    std.testing.refAllDecls(@This());
}
