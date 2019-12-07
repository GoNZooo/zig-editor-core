pub const string = @import("./string.zig");
pub const file_buffer_tests = @import("./file_buffer_tests.zig");
pub const vim_tests = @import("./vim_tests.zig");

test "run tests" {
    string.runTests();
    file_buffer_tests.runTests();
    vim_tests.runTests();
}
