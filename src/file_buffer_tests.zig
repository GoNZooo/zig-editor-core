const file_buffer = @import("./file_buffer.zig");
const FileBuffer = file_buffer.FileBuffer;
const FileBufferOptions = file_buffer.FileBufferOptions;
const AppendCopyOptions = file_buffer.AppendCopyOptions;
const RemoveOptions = file_buffer.RemoveOptions;
const InsertCopyOptions = file_buffer.InsertCopyOptions;
const String = @import("./string.zig").String;

const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const direct_allocator = std.heap.direct_allocator;

test "`deinit` frees the memory in the `FileBuffer`" {
    var buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{});
    testing.expectEqual(buffer.count, 0);

    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "there");
    const lines_to_add = ([_]String(u8){ string1, string2 })[0..];
    try buffer.append(direct_allocator, lines_to_add);
    const buffer_lines = buffer.lines();
    const buffer_line_1_content = buffer_lines[0].__chars;
    testing.expectEqual(buffer.count, 2);
    testing.expectEqual(buffer.capacity, 2);
    buffer.deinit();
}

test "`deinit` frees the memory in the `FileBuffer` without `deinit()` present" {
    var buffer = try FileBuffer([]u8).init(direct_allocator, FileBufferOptions{});
    var string1 = try mem.dupe(direct_allocator, u8, "hello"[0..]);
    var string2 = try mem.dupe(direct_allocator, u8, "there"[0..]);
    var string3 = try mem.dupe(direct_allocator, u8, "handsome"[0..]);
    const lines_to_add = ([_][]u8{ string1, string2, string3 })[0..];
    try buffer.append(direct_allocator, lines_to_add);
    const buffer_lines = buffer.lines();
    testing.expectEqual(buffer.count, 3);
    testing.expectEqual(buffer.capacity, 3);
    buffer.deinit();
}

test "`append` appends lines" {
    var buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{});
    testing.expectEqual(buffer.count, 0);

    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "there");
    const lines_to_add = ([_]String(u8){ string1, string2 })[0..];
    try buffer.append(direct_allocator, lines_to_add);

    testing.expectEqual(buffer.count, 2);
    testing.expectEqual(buffer.capacity, 2);
    for (buffer.lines()) |line, i| {
        testing.expectEqualSlices(u8, line.sliceConst(), lines_to_add[i].sliceConst());
        testing.expect(&line != &lines_to_add[i]);
    }
}

test "`append` appends lines but doesn't increase capacity if already sufficient" {
    var buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{
        .initial_capacity = 120,
    });
    testing.expectEqual(buffer.count, 0);

    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "there");

    const lines_to_add = ([_]String(u8){ string1, string2 })[0..];
    try buffer.append(direct_allocator, lines_to_add);
    testing.expectEqual(buffer.count, 2);
    testing.expectEqual(buffer.capacity, 120);
    for (buffer.lines()) |line, i| {
        testing.expectEqualSlices(u8, line.sliceConst(), lines_to_add[i].sliceConst());
    }
}

test "`appendCopy` appends lines" {
    var buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{
        .initial_capacity = 120,
    });
    testing.expectEqual(buffer.count, 0);

    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "there");

    const lines_to_add = ([_]String(u8){ string1, string2 })[0..];
    var buffer2 = try buffer.appendCopy(
        direct_allocator,
        lines_to_add,
        AppendCopyOptions{},
    );
    testing.expectEqual(buffer2.count, 2);
    testing.expectEqual(buffer2.capacity, 120);
    for (buffer2.lines()) |line, i| {
        testing.expectEqualSlices(u8, line.sliceConst(), lines_to_add[i].sliceConst());
    }
    testing.expectEqual(buffer.count, 0);
    testing.expectEqual(buffer.capacity, 120);
}

test "`appendCopy` appends lines and shrinks if given the option" {
    var buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{
        .initial_capacity = 120,
    });
    testing.expectEqual(buffer.count, 0);

    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "there");

    const lines_to_add = ([_]String(u8){ string1, string2 })[0..];
    var buffer2 = try buffer.appendCopy(
        direct_allocator,
        lines_to_add,
        AppendCopyOptions{ .shrink = true },
    );
    testing.expectEqual(buffer2.count, 2);
    testing.expectEqual(buffer2.capacity, 2);
    for (buffer2.lines()) |line, i| {
        testing.expectEqualSlices(u8, line.sliceConst(), lines_to_add[i].sliceConst());
    }
    testing.expectEqual(buffer.count, 0);
    testing.expectEqual(buffer.capacity, 120);
}

test "`insert` inserts lines" {
    var buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{});
    testing.expectEqual(buffer.count, 0);

    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "you");
    const string3 = try String(u8).copyConst(direct_allocator, "!");
    const lines_to_add = ([_]String(u8){ string1, string2, string3 })[0..];
    try buffer.append(direct_allocator, lines_to_add);
    const string4 = try String(u8).copyConst(direct_allocator, "there,");
    const string5 = try String(u8).copyConst(direct_allocator, "you");
    const string6 = try String(u8).copyConst(direct_allocator, "handsome");
    const string7 = try String(u8).copyConst(direct_allocator, "devil");
    const lines_to_insert = ([_]String(u8){ string4, string5, string6, string7 })[0..];
    try buffer.insert(1, lines_to_insert);
    testing.expectEqual(buffer.count, 7);
    testing.expectEqual(buffer.capacity, 7);
    testing.expectEqualSlices(u8, buffer.lines()[0].sliceConst(), "hello");
    testing.expectEqualSlices(u8, buffer.lines()[1].sliceConst(), "there,");
    testing.expectEqualSlices(u8, buffer.lines()[2].sliceConst(), "you");
    testing.expectEqualSlices(u8, buffer.lines()[3].sliceConst(), "handsome");
    testing.expectEqualSlices(u8, buffer.lines()[4].sliceConst(), "devil");
    testing.expectEqualSlices(u8, buffer.lines()[5].sliceConst(), "you");
    testing.expectEqualSlices(u8, buffer.lines()[6].sliceConst(), "!");
}

test "`insertCopy` inserts lines" {
    var buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{});
    testing.expectEqual(buffer.count, 0);

    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "you");
    const string3 = try String(u8).copyConst(direct_allocator, "!");
    const lines_to_add = ([_]String(u8){ string1, string2, string3 })[0..];
    try buffer.append(direct_allocator, lines_to_add);
    const string4 = try String(u8).copyConst(direct_allocator, "there,");
    const string5 = try String(u8).copyConst(direct_allocator, "you");
    const string6 = try String(u8).copyConst(direct_allocator, "handsome");
    const string7 = try String(u8).copyConst(direct_allocator, "devil");
    const lines_to_insert = ([_]String(u8){ string4, string5, string6, string7 })[0..];
    var buffer2 = try buffer.insertCopy(
        direct_allocator,
        1,
        lines_to_insert,
        InsertCopyOptions{},
    );
    testing.expectEqual(buffer2.count, 7);
    testing.expectEqual(buffer2.capacity, 7);
    testing.expectEqualSlices(u8, buffer2.lines()[0].sliceConst(), "hello");
    testing.expectEqualSlices(u8, buffer2.lines()[1].sliceConst(), "there,");
    testing.expectEqualSlices(u8, buffer2.lines()[2].sliceConst(), "you");
    testing.expectEqualSlices(u8, buffer2.lines()[3].sliceConst(), "handsome");
    testing.expectEqualSlices(u8, buffer2.lines()[4].sliceConst(), "devil");
    testing.expectEqualSlices(u8, buffer2.lines()[5].sliceConst(), "you");
    testing.expectEqualSlices(u8, buffer2.lines()[6].sliceConst(), "!");
}

test "`insertCopy` inserts lines and doesn't shrink unless told otherwise" {
    var buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{
        .initial_capacity = 80,
    });
    testing.expectEqual(buffer.count, 0);
    testing.expectEqual(buffer.capacity, 80);

    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "you");
    const string3 = try String(u8).copyConst(direct_allocator, "!");
    const lines_to_add = ([_]String(u8){ string1, string2, string3 })[0..];
    try buffer.append(direct_allocator, lines_to_add);
    const string4 = try String(u8).copyConst(direct_allocator, "there,");
    const string5 = try String(u8).copyConst(direct_allocator, "you");
    const string6 = try String(u8).copyConst(direct_allocator, "handsome");
    const string7 = try String(u8).copyConst(direct_allocator, "devil");
    const lines_to_insert = ([_]String(u8){ string4, string5, string6, string7 })[0..];
    var buffer2 = try buffer.insertCopy(
        direct_allocator,
        1,
        lines_to_insert,
        InsertCopyOptions{},
    );
    testing.expectEqual(buffer2.count, 7);
    testing.expectEqual(buffer2.capacity, 80);
    testing.expectEqualSlices(u8, buffer2.lines()[0].sliceConst(), "hello");
    testing.expectEqualSlices(u8, buffer2.lines()[1].sliceConst(), "there,");
    testing.expectEqualSlices(u8, buffer2.lines()[2].sliceConst(), "you");
    testing.expectEqualSlices(u8, buffer2.lines()[3].sliceConst(), "handsome");
    testing.expectEqualSlices(u8, buffer2.lines()[4].sliceConst(), "devil");
    testing.expectEqualSlices(u8, buffer2.lines()[5].sliceConst(), "you");
    testing.expectEqualSlices(u8, buffer2.lines()[6].sliceConst(), "!");
}

test "`insertCopy` inserts lines and shrinks if told to do so" {
    var buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{
        .initial_capacity = 80,
    });
    testing.expectEqual(buffer.count, 0);
    testing.expectEqual(buffer.capacity, 80);

    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "you");
    const string3 = try String(u8).copyConst(direct_allocator, "!");
    const lines_to_add = ([_]String(u8){ string1, string2, string3 })[0..];
    try buffer.append(direct_allocator, lines_to_add);
    const string4 = try String(u8).copyConst(direct_allocator, "there,");
    const string5 = try String(u8).copyConst(direct_allocator, "you");
    const string6 = try String(u8).copyConst(direct_allocator, "handsome");
    const string7 = try String(u8).copyConst(direct_allocator, "devil");
    const lines_to_insert = ([_]String(u8){ string4, string5, string6, string7 })[0..];
    var buffer2 = try buffer.insertCopy(direct_allocator, 1, lines_to_insert, InsertCopyOptions{
        .shrink = true,
    });
    testing.expectEqual(buffer2.count, 7);
    testing.expectEqual(buffer2.capacity, 7);
    testing.expectEqualSlices(u8, buffer2.lines()[0].sliceConst(), "hello");
    testing.expectEqualSlices(u8, buffer2.lines()[1].sliceConst(), "there,");
    testing.expectEqualSlices(u8, buffer2.lines()[2].sliceConst(), "you");
    testing.expectEqualSlices(u8, buffer2.lines()[3].sliceConst(), "handsome");
    testing.expectEqualSlices(u8, buffer2.lines()[4].sliceConst(), "devil");
    testing.expectEqualSlices(u8, buffer2.lines()[5].sliceConst(), "you");
    testing.expectEqualSlices(u8, buffer2.lines()[6].sliceConst(), "!");
}

test "`remove` removes" {
    var buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{});
    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "there");
    const string3 = try String(u8).copyConst(direct_allocator, "handsome");
    const lines_to_add = ([_]String(u8){ string1, string2, string3 })[0..];
    try buffer.append(direct_allocator, lines_to_add);
    buffer.remove(1, 2, RemoveOptions{});
    testing.expectEqual(buffer.capacity, 3);
    testing.expectEqual(buffer.count, 2);
    testing.expectEqualSlices(u8, buffer.lines()[0].sliceConst(), string1.sliceConst());
    testing.expectEqualSlices(u8, buffer.lines()[1].sliceConst(), string3.sliceConst());
}

test "`remove` removes and shrinks when `shrink` option is `true`" {
    var buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{});
    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "there");
    const string3 = try String(u8).copyConst(direct_allocator, "handsome");
    const lines_to_add = ([_]String(u8){ string1, string2, string3 })[0..];
    try buffer.append(direct_allocator, lines_to_add);
    buffer.remove(1, 2, RemoveOptions{ .shrink = true });
    testing.expectEqual(buffer.capacity, 2);
    testing.expectEqual(buffer.count, 2);
    testing.expectEqualSlices(u8, buffer.lines()[0].sliceConst(), string1.sliceConst());
    testing.expectEqualSlices(u8, buffer.lines()[1].sliceConst(), string3.sliceConst());
}

test "`remove` removes when type does not have `deinit()`" {
    var buffer = try FileBuffer([]u8).init(direct_allocator, FileBufferOptions{});
    var string1 = try mem.dupe(direct_allocator, u8, "hello"[0..]);
    var string2 = try mem.dupe(direct_allocator, u8, "there"[0..]);
    var string3 = try mem.dupe(direct_allocator, u8, "handsome"[0..]);
    const lines_to_add = ([_][]u8{ string1, string2, string3 })[0..];
    try buffer.append(direct_allocator, lines_to_add);
    buffer.remove(1, 2, RemoveOptions{});
    testing.expectEqual(buffer.capacity, 3);
    testing.expectEqual(buffer.count, 2);
    testing.expectEqualSlices(u8, buffer.lines()[0], string1);
    testing.expectEqualSlices(u8, buffer.lines()[1], string3);
}

test "`removeCopy` removes and gives a new `FileBuffer`" {
    var buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{});
    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "there");
    const string3 = try String(u8).copyConst(direct_allocator, "handsome");
    const lines_to_add = ([_]String(u8){ string1, string2, string3 })[0..];
    try buffer.append(direct_allocator, lines_to_add);
    var buffer2 = try buffer.removeCopy(direct_allocator, 1, 2, RemoveOptions{});
    testing.expectEqual(buffer2.capacity, 3);
    testing.expectEqual(buffer2.count, 2);
    testing.expectEqualSlices(u8, buffer2.lines()[0].sliceConst(), string1.sliceConst());
    testing.expectEqualSlices(u8, buffer2.lines()[1].sliceConst(), string3.sliceConst());
}

test "`removeCopy` removes and gives a new `FileBuffer` and can shrink" {
    var buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{});
    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "there");
    const string3 = try String(u8).copyConst(direct_allocator, "handsome");
    const lines_to_add = ([_]String(u8){ string1, string2, string3 })[0..];
    try buffer.append(direct_allocator, lines_to_add);
    var buffer2 = try buffer.removeCopy(direct_allocator, 1, 2, RemoveOptions{
        .shrink = true,
    });
    testing.expectEqual(buffer2.capacity, 2);
    testing.expectEqual(buffer2.count, 2);
    testing.expectEqualSlices(u8, buffer2.lines()[0].sliceConst(), string1.sliceConst());
    testing.expectEqualSlices(u8, buffer2.lines()[1].sliceConst(), string3.sliceConst());
}

const test1_path = switch (std.builtin.os) {
    .windows => "data\\file_buffer_tests\\test1.txt",
    else => "data/file_buffer_tests/test1.txt",
};

const test1_newline_delimiter = switch (std.builtin.os) {
    .windows => "\r\n",
    else => "\n",
};

test "`fromRelativeFile` reads a file properly into the buffer" {
    var buffer = try FileBuffer(String(u8)).fromRelativeFile(
        direct_allocator,
        test1_path,
        test1_newline_delimiter,
        FileBufferOptions{},
    );

    const lines = buffer.lines();
    const line1 = lines[0].sliceConst();
    const line2 = lines[1].sliceConst();
    const line3 = lines[2].sliceConst();
    const line4 = lines[3].sliceConst();
    const line5 = lines[4].sliceConst();

    testing.expectEqualSlices(u8, line1, "hello");
    testing.expectEqualSlices(u8, line2, "");
    testing.expectEqualSlices(u8, line3, "there");
    testing.expectEqualSlices(u8, line4, "you handsome");
    testing.expectEqualSlices(u8, line5, "devil, you");
}

pub fn runTests() void {}
