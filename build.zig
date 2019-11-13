const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("editor-core", "src/main.zig");
    lib.setBuildMode(mode);
    lib.install();

    var string_tests = b.addTest("src/string.zig");
    string_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&string_tests.step);
}
