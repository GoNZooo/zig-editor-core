const BufferState = @import("./buffer_state.zig").BufferState;
const vim = @import("./vim.zig");
const Command = vim.Command;
const CommandData = vim.CommandData;
const Motion = vim.Motion;
const file_buffer = @import("./file_buffer.zig");
const FromFileOptions = file_buffer.FromFileOptions;
const String = @import("./string.zig").String;
const FileBufferOptions = file_buffer.FileBufferOptions;

const std = @import("std");
const direct_allocator = std.heap.direct_allocator;
const testing = std.testing;
const meta = std.meta;

test "`init` works" {
    var buffer_state = try BufferState(String(u8), String(u8).copyConst).init(
        direct_allocator,
        FileBufferOptions{},
    );
    testing.expect(meta.activeTag(buffer_state.vim_state) == .Start);
}

test "`deinit` works" {
    var buffer_state = try BufferState(String(u8), String(u8).copyConst).init(
        direct_allocator,
        FileBufferOptions{},
    );
    buffer_state.deinit();
}

const test_file_path = switch (std.builtin.os) {
    .windows => "data\\file_buffer_tests\\test1.txt",
    else => "data/file_buffer_tests/test1.txt",
};

test "supports `loadRelativeFile`" {
    const command = Command{
        .MotionOnly = CommandData{
            .motion = Motion{ .UntilNextWord = 1 },
            .register = null,
        },
    };

    var buffer_state = try BufferState(String(u8), String(u8).copyConst).init(
        direct_allocator,
        FileBufferOptions{},
    );

    try buffer_state.loadRelativeFile(
        direct_allocator,
        test_file_path,
        FromFileOptions{ .max_size = 128 },
    );

    const lines = buffer_state.buffer.lines();

    const line1 = lines[0].sliceConst();
    testing.expectEqualSlices(u8, line1, "hello");

    const line2 = lines[1].sliceConst();
    testing.expectEqualSlices(u8, line2, "");

    const line3 = lines[2].sliceConst();
    testing.expectEqualSlices(u8, line3, "there");

    const line4 = lines[3].sliceConst();
    testing.expectEqualSlices(u8, line4, "you handsome");

    const line5 = lines[4].sliceConst();
    testing.expectEqualSlices(u8, line5, "devil, you");
}
