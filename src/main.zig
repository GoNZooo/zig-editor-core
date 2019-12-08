test "run tests" {
    _ = @import("./string.zig");
    _ = @import("./file_buffer_tests.zig");
    _ = @import("./vim_tests.zig");
    _ = @import("./buffer_state_tests.zig");
}
