const std = @import("std");
const page_allocator = std.heap.page_allocator;
const testing = std.testing;
const meta = std.meta;
const debug = std.debug;

const buffer_state = @import("./buffer_state.zig");
const BufferState = buffer_state.BufferState;
const BufferStateOptions = buffer_state.BufferStateOptions;
const vim = @import("./vim.zig");
const Command = vim.Command;
const CommandData = vim.CommandData;
const Motion = vim.Motion;
const file_buffer = @import("./file_buffer.zig");
const FromFileOptions = file_buffer.FromFileOptions;
const String = @import("./string.zig").String;
const FileBufferOptions = file_buffer.FileBufferOptions;

const U8BufferState = BufferState(String(u8), String(u8).copyConst);

test "`init` works" {
    var state = try U8BufferState.init(
        page_allocator,
        BufferStateOptions{},
        FileBufferOptions{},
    );
    testing.expect(meta.activeTag(state.vim_state) == .Start);
}

test "`deinit` works" {
    var state = try U8BufferState.init(
        page_allocator,
        BufferStateOptions{},
        FileBufferOptions{},
    );
    state.deinit();
}

const test_file_path = switch (std.builtin.os.tag) {
    .windows => "data\\file_buffer_tests\\test1.txt",
    else => "data/file_buffer_tests/test1.txt",
};

test "supports `loadRelativeFile`" {
    var state = try U8BufferState.init(
        page_allocator,
        BufferStateOptions{},
        FileBufferOptions{},
    );

    testing.expectEqual(state.cursor.column, 0);
    testing.expectEqual(state.cursor.line, 0);

    try state.loadRelativeFile(
        page_allocator,
        test_file_path,
        FromFileOptions{ .max_size = 128 },
    );

    const lines = state.buffer.lines();

    const line1 = lines[0].sliceConst();
    testing.expectEqualStrings(line1, "hello");

    const line2 = lines[1].sliceConst();
    testing.expectEqualStrings(line2, "");

    const line3 = lines[2].sliceConst();
    testing.expectEqualStrings(line3, "there");

    const line4 = lines[3].sliceConst();
    testing.expectEqualStrings(line4, "you    handsome ");

    const line5 = lines[4].sliceConst();
    testing.expectEqualStrings(line5, "devil, you");
}

test "`init` with `path_to_relative_file` loads file immediately" {
    var state = try U8BufferState.init(
        page_allocator,
        BufferStateOptions{
            .path_to_relative_file = test_file_path,
            .from_file_options = FromFileOptions{
                .max_size = 128,
            },
        },
        FileBufferOptions{},
    );

    testing.expectEqual(state.cursor.column, 0);
    testing.expectEqual(state.cursor.line, 0);

    const lines = state.buffer.lines();

    const line1 = lines[0].sliceConst();
    testing.expectEqualStrings(line1, "hello");

    const line2 = lines[1].sliceConst();
    testing.expectEqualStrings(line2, "");

    const line3 = lines[2].sliceConst();
    testing.expectEqualStrings(line3, "there");

    const line4 = lines[3].sliceConst();
    testing.expectEqualStrings(line4, "you    handsome ");

    const line5 = lines[4].sliceConst();
    testing.expectEqualStrings(line5, "devil, you");
}

test "`handleKey` handles `w` & `b` properly" {
    var state = try U8BufferState.init(
        page_allocator,
        BufferStateOptions{
            .path_to_relative_file = test_file_path,
            .from_file_options = FromFileOptions{ .max_size = 128 },
        },
        FileBufferOptions{},
    );

    testing.expectEqual(state.cursor.column, 0);
    testing.expectEqual(state.cursor.line, 0);

    const w = vim.Key{ .key_code = 'w' };

    try state.handleKey(w);
    testing.expectEqual(state.cursor.line, 1);
    testing.expectEqual(state.cursor.column, 0);

    try state.handleKey(w);
    testing.expectEqual(state.cursor.line, 2);
    testing.expectEqual(state.cursor.column, 0);

    try state.handleKey(w);
    testing.expectEqual(state.cursor.line, 3);
    testing.expectEqual(state.cursor.column, 0);

    try state.handleKey(w);
    testing.expectEqual(state.cursor.line, 3);
    testing.expectEqual(state.cursor.column, 7);

    try state.handleKey(w);
    testing.expectEqual(state.cursor.line, 4);
    testing.expectEqual(state.cursor.column, 0);

    try state.handleKey(w);
    testing.expectEqual(state.cursor.line, 4);
    testing.expectEqual(state.cursor.column, 5);

    try state.handleKey(w);
    testing.expectEqual(state.cursor.line, 4);
    testing.expectEqual(state.cursor.column, 7);

    const b = vim.Key{ .key_code = 'b' };

    try state.handleKey(b);
    testing.expectEqual(state.cursor.line, 4);
    testing.expectEqual(state.cursor.column, 5);

    try state.handleKey(b);
    testing.expectEqual(state.cursor.line, 4);
    testing.expectEqual(state.cursor.column, 0);

    try state.handleKey(b);
    testing.expectEqual(state.cursor.line, 3);
    testing.expectEqual(state.cursor.column, 7);

    try state.handleKey(b);
    testing.expectEqual(state.cursor.line, 3);
    testing.expectEqual(state.cursor.column, 0);

    try state.handleKey(b);
    testing.expectEqual(state.cursor.line, 2);
    testing.expectEqual(state.cursor.column, 0);

    try state.handleKey(b);
    testing.expectEqual(state.cursor.line, 1);
    testing.expectEqual(state.cursor.column, 0);

    try state.handleKey(b);
    testing.expectEqual(state.cursor.line, 0);
    testing.expectEqual(state.cursor.column, 0);
}

// @TODO: add tests for ranged "Until..." motions
