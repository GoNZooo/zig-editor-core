pub const string = @import("./string.zig");
pub const file_buffer = @import("./file_buffer.zig");
pub const vim_tests = @import("./vim_tests.zig");

test "run tests" {
    string.runTests();
    file_buffer.runTests();
    vim_tests.runTests();
}
