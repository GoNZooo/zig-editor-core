const file_buffer = @import("./file_buffer.zig");
const FileBuffer = file_buffer.FileBuffer;
const FileBufferOptions = file_buffer.FileBufferOptions;
const AppendCopyOptions = file_buffer.AppendCopyOptions;
const RemoveOptions = file_buffer.RemoveOptions;
const InsertCopyOptions = file_buffer.InsertCopyOptions;
const FromFileOptions = file_buffer.FromFileOptions;
const String = @import("./string.zig").String;

const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const debug = std.debug;
const heap = std.heap;

const U8FileBuffer = FileBuffer(String(u8), String(u8).copyConst);

test "`deinit` frees the memory in the `FileBuffer`" {
    var testing_allocator = testing.LeakCountAllocator.init(heap.page_allocator);
    var buffer = try U8FileBuffer.init(
        &testing_allocator.allocator,
        FileBufferOptions{},
    );
    testing.expectEqual(buffer.count, 0);

    const string1 = try String(u8).copyConst(&testing_allocator.allocator, "hello");
    const string2 = try String(u8).copyConst(&testing_allocator.allocator, "there");
    const lines_to_add = ([_]String(u8){ string1, string2 })[0..];
    try buffer.append(&testing_allocator.allocator, lines_to_add);
    const buffer_lines = buffer.lines();
    const buffer_line_1_content = buffer_lines[0].__chars;
    testing.expectEqual(buffer.count, 2);
    testing.expectEqual(buffer.capacity, 2);
    buffer.deinit();
    try testing_allocator.validate();
}

fn u8ToU8(allocator: *mem.Allocator, string: []const u8) ![]u8 {
    var copied = try mem.dupe(allocator, u8, string);

    return copied;
}

test "`deinit` frees the memory in the `FileBuffer` without `deinit()` present" {
    var testing_allocator = testing.LeakCountAllocator.init(heap.page_allocator);
    var buffer = try FileBuffer([]u8, u8ToU8).init(&testing_allocator.allocator, FileBufferOptions{});
    var string1 = try mem.dupe(&testing_allocator.allocator, u8, "hello"[0..]);
    var string2 = try mem.dupe(&testing_allocator.allocator, u8, "there"[0..]);
    var string3 = try mem.dupe(&testing_allocator.allocator, u8, "handsome"[0..]);
    const lines_to_add = ([_][]u8{ string1, string2, string3 })[0..];
    try buffer.append(&testing_allocator.allocator, lines_to_add);
    const buffer_lines = buffer.lines();
    testing.expectEqual(buffer.count, 3);
    testing.expectEqual(buffer.capacity, 3);
    buffer.deinit();
    testing_allocator.allocator.free(string1);
    testing_allocator.allocator.free(string2);
    testing_allocator.allocator.free(string3);
    try testing_allocator.validate();
}

test "`append` appends lines" {
    var buffer = try U8FileBuffer.init(
        heap.page_allocator,
        FileBufferOptions{},
    );
    testing.expectEqual(buffer.count, 0);

    const string1 = try String(u8).copyConst(heap.page_allocator, "hello");
    const string2 = try String(u8).copyConst(heap.page_allocator, "there");
    const lines_to_add = ([_]String(u8){ string1, string2 })[0..];
    try buffer.append(heap.page_allocator, lines_to_add);

    testing.expectEqual(buffer.count, 2);
    testing.expectEqual(buffer.capacity, 2);
    for (buffer.lines()) |line, i| {
        testing.expectEqualSlices(u8, line.sliceConst(), lines_to_add[i].sliceConst());
        testing.expect(&line != &lines_to_add[i]);
    }
}

test "`append` appends lines but doesn't increase capacity if already sufficient" {
    var buffer = try U8FileBuffer.init(heap.page_allocator, FileBufferOptions{
        .initial_capacity = 120,
    });
    testing.expectEqual(buffer.count, 0);

    const string1 = try String(u8).copyConst(heap.page_allocator, "hello");
    const string2 = try String(u8).copyConst(heap.page_allocator, "there");

    const lines_to_add = ([_]String(u8){ string1, string2 })[0..];
    try buffer.append(heap.page_allocator, lines_to_add);
    testing.expectEqual(buffer.count, 2);
    testing.expectEqual(buffer.capacity, 120);
    for (buffer.lines()) |line, i| {
        testing.expectEqualSlices(u8, line.sliceConst(), lines_to_add[i].sliceConst());
    }
}

test "`appendCopy` appends lines" {
    var buffer = try U8FileBuffer.init(heap.page_allocator, FileBufferOptions{
        .initial_capacity = 120,
    });
    testing.expectEqual(buffer.count, 0);

    const string1 = try String(u8).copyConst(heap.page_allocator, "hello");
    const string2 = try String(u8).copyConst(heap.page_allocator, "there");

    const lines_to_add = ([_]String(u8){ string1, string2 })[0..];
    var buffer2 = try buffer.appendCopy(
        heap.page_allocator,
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
    var buffer = try U8FileBuffer.init(
        heap.page_allocator,
        FileBufferOptions{
            .initial_capacity = 120,
        },
    );
    testing.expectEqual(buffer.count, 0);

    const string1 = try String(u8).copyConst(heap.page_allocator, "hello");
    const string2 = try String(u8).copyConst(heap.page_allocator, "there");

    const lines_to_add = ([_]String(u8){ string1, string2 })[0..];
    var buffer2 = try buffer.appendCopy(
        heap.page_allocator,
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
    var buffer = try U8FileBuffer.init(
        heap.page_allocator,
        FileBufferOptions{},
    );
    testing.expectEqual(buffer.count, 0);

    const string1 = try String(u8).copyConst(heap.page_allocator, "hello");
    const string2 = try String(u8).copyConst(heap.page_allocator, "you");
    const string3 = try String(u8).copyConst(heap.page_allocator, "!");
    const lines_to_add = ([_]String(u8){ string1, string2, string3 })[0..];
    try buffer.append(heap.page_allocator, lines_to_add);

    const string4 = try String(u8).copyConst(heap.page_allocator, "there,");
    const string5 = try String(u8).copyConst(heap.page_allocator, "you");
    const string6 = try String(u8).copyConst(heap.page_allocator, "handsome");
    const string7 = try String(u8).copyConst(heap.page_allocator, "devil");
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

test "`insert` inserts 'shaka'" {
    var buffer = try U8FileBuffer.init(
        heap.page_allocator,
        FileBufferOptions{},
    );
    testing.expectEqual(buffer.count, 0);

    const string1 = try String(u8).copyConst(heap.page_allocator, "boom");
    const string3 = try String(u8).copyConst(heap.page_allocator, "laka");
    const lines_to_add = ([_]String(u8){ string1, string3 })[0..];
    try buffer.append(heap.page_allocator, lines_to_add);

    const string2 = try String(u8).copyConst(heap.page_allocator, "shaka");
    const lines_to_insert = ([_]String(u8){string2})[0..];
    try buffer.insert(1, lines_to_insert);

    testing.expectEqual(buffer.count, 3);
    testing.expectEqual(buffer.capacity, 3);
    testing.expectEqualSlices(u8, buffer.lines()[0].sliceConst(), "boom");
    testing.expectEqualSlices(u8, buffer.lines()[1].sliceConst(), "shaka");
    testing.expectEqualSlices(u8, buffer.lines()[2].sliceConst(), "laka");
}

test "`insertCopy` inserts lines" {
    var buffer = try U8FileBuffer.init(heap.page_allocator, FileBufferOptions{});
    testing.expectEqual(buffer.count, 0);

    const string1 = try String(u8).copyConst(heap.page_allocator, "hello");
    const string2 = try String(u8).copyConst(heap.page_allocator, "you");
    const string3 = try String(u8).copyConst(heap.page_allocator, "!");
    const lines_to_add = ([_]String(u8){ string1, string2, string3 })[0..];
    try buffer.append(heap.page_allocator, lines_to_add);
    const string4 = try String(u8).copyConst(heap.page_allocator, "there,");
    const string5 = try String(u8).copyConst(heap.page_allocator, "you");
    const string6 = try String(u8).copyConst(heap.page_allocator, "handsome");
    const string7 = try String(u8).copyConst(heap.page_allocator, "devil");
    const lines_to_insert = ([_]String(u8){ string4, string5, string6, string7 })[0..];
    var buffer2 = try buffer.insertCopy(
        heap.page_allocator,
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
    var buffer = try U8FileBuffer.init(heap.page_allocator, FileBufferOptions{
        .initial_capacity = 80,
    });
    testing.expectEqual(buffer.count, 0);
    testing.expectEqual(buffer.capacity, 80);

    const string1 = try String(u8).copyConst(heap.page_allocator, "hello");
    const string2 = try String(u8).copyConst(heap.page_allocator, "you");
    const string3 = try String(u8).copyConst(heap.page_allocator, "!");
    const lines_to_add = ([_]String(u8){ string1, string2, string3 })[0..];
    try buffer.append(heap.page_allocator, lines_to_add);
    const string4 = try String(u8).copyConst(heap.page_allocator, "there,");
    const string5 = try String(u8).copyConst(heap.page_allocator, "you");
    const string6 = try String(u8).copyConst(heap.page_allocator, "handsome");
    const string7 = try String(u8).copyConst(heap.page_allocator, "devil");
    const lines_to_insert = ([_]String(u8){ string4, string5, string6, string7 })[0..];
    var buffer2 = try buffer.insertCopy(
        heap.page_allocator,
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
    var buffer = try U8FileBuffer.init(heap.page_allocator, FileBufferOptions{
        .initial_capacity = 80,
    });
    testing.expectEqual(buffer.count, 0);
    testing.expectEqual(buffer.capacity, 80);

    const string1 = try String(u8).copyConst(heap.page_allocator, "hello");
    const string2 = try String(u8).copyConst(heap.page_allocator, "you");
    const string3 = try String(u8).copyConst(heap.page_allocator, "!");
    const lines_to_add = ([_]String(u8){ string1, string2, string3 })[0..];
    try buffer.append(heap.page_allocator, lines_to_add);
    const string4 = try String(u8).copyConst(heap.page_allocator, "there,");
    const string5 = try String(u8).copyConst(heap.page_allocator, "you");
    const string6 = try String(u8).copyConst(heap.page_allocator, "handsome");
    const string7 = try String(u8).copyConst(heap.page_allocator, "devil");
    const lines_to_insert = ([_]String(u8){ string4, string5, string6, string7 })[0..];
    var buffer2 = try buffer.insertCopy(heap.page_allocator, 1, lines_to_insert, InsertCopyOptions{
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
    var buffer = try U8FileBuffer.init(heap.page_allocator, FileBufferOptions{});
    const string1 = try String(u8).copyConst(heap.page_allocator, "hello");
    const string2 = try String(u8).copyConst(heap.page_allocator, "there");
    const string3 = try String(u8).copyConst(heap.page_allocator, "handsome");
    const lines_to_add = ([_]String(u8){ string1, string2, string3 })[0..];
    try buffer.append(heap.page_allocator, lines_to_add);
    buffer.remove(1, 2, RemoveOptions{});
    testing.expectEqual(buffer.capacity, 3);
    testing.expectEqual(buffer.count, 2);
    testing.expectEqualSlices(u8, buffer.lines()[0].sliceConst(), string1.sliceConst());
    testing.expectEqualSlices(u8, buffer.lines()[1].sliceConst(), string3.sliceConst());
}

test "`remove` removes and shrinks when `shrink` option is `true`" {
    var buffer = try U8FileBuffer.init(heap.page_allocator, FileBufferOptions{});
    const string1 = try String(u8).copyConst(heap.page_allocator, "hello");
    const string2 = try String(u8).copyConst(heap.page_allocator, "there");
    const string3 = try String(u8).copyConst(heap.page_allocator, "handsome");
    const lines_to_add = ([_]String(u8){ string1, string2, string3 })[0..];
    try buffer.append(heap.page_allocator, lines_to_add);
    buffer.remove(1, 2, RemoveOptions{ .shrink = true });
    testing.expectEqual(buffer.capacity, 2);
    testing.expectEqual(buffer.count, 2);
    testing.expectEqualSlices(u8, buffer.lines()[0].sliceConst(), string1.sliceConst());
    testing.expectEqualSlices(u8, buffer.lines()[1].sliceConst(), string3.sliceConst());
}

test "`remove` removes when type does not have `deinit()`" {
    var buffer = try FileBuffer([]u8, u8ToU8).init(heap.page_allocator, FileBufferOptions{});
    var string1 = try mem.dupe(heap.page_allocator, u8, "hello"[0..]);
    var string2 = try mem.dupe(heap.page_allocator, u8, "there"[0..]);
    var string3 = try mem.dupe(heap.page_allocator, u8, "handsome"[0..]);
    const lines_to_add = ([_][]u8{ string1, string2, string3 })[0..];
    try buffer.append(heap.page_allocator, lines_to_add);
    buffer.remove(1, 2, RemoveOptions{});
    testing.expectEqual(buffer.capacity, 3);
    testing.expectEqual(buffer.count, 2);
    testing.expectEqualSlices(u8, buffer.lines()[0], string1);
    testing.expectEqualSlices(u8, buffer.lines()[1], string3);
}

test "`removeCopy` removes and gives a new `FileBuffer`" {
    var buffer = try U8FileBuffer.init(heap.page_allocator, FileBufferOptions{});
    const string1 = try String(u8).copyConst(heap.page_allocator, "hello");
    const string2 = try String(u8).copyConst(heap.page_allocator, "there");
    const string3 = try String(u8).copyConst(heap.page_allocator, "handsome");
    const lines_to_add = ([_]String(u8){ string1, string2, string3 })[0..];
    try buffer.append(heap.page_allocator, lines_to_add);
    var buffer2 = try buffer.removeCopy(heap.page_allocator, 1, 2, RemoveOptions{});
    testing.expectEqual(buffer2.capacity, 3);
    testing.expectEqual(buffer2.count, 2);
    testing.expectEqualSlices(u8, buffer2.lines()[0].sliceConst(), string1.sliceConst());
    testing.expectEqualSlices(u8, buffer2.lines()[1].sliceConst(), string3.sliceConst());
}

test "`removeCopy` removes and gives a new `FileBuffer` and can shrink" {
    var buffer = try U8FileBuffer.init(heap.page_allocator, FileBufferOptions{});
    const string1 = try String(u8).copyConst(heap.page_allocator, "hello");
    const string2 = try String(u8).copyConst(heap.page_allocator, "there");
    const string3 = try String(u8).copyConst(heap.page_allocator, "handsome");
    const lines_to_add = ([_]String(u8){ string1, string2, string3 })[0..];
    try buffer.append(heap.page_allocator, lines_to_add);
    var buffer2 = try buffer.removeCopy(heap.page_allocator, 1, 2, RemoveOptions{
        .shrink = true,
    });
    testing.expectEqual(buffer2.capacity, 2);
    testing.expectEqual(buffer2.count, 2);
    testing.expectEqualSlices(u8, buffer2.lines()[0].sliceConst(), string1.sliceConst());
    testing.expectEqualSlices(u8, buffer2.lines()[1].sliceConst(), string3.sliceConst());
}

const test1_path = switch (std.builtin.os.tag) {
    .windows => "data\\file_buffer_tests\\test1.txt",
    else => "data/file_buffer_tests/test1.txt",
};

test "`fromRelativeFile` reads a file properly into the buffer" {
    var buffer = try U8FileBuffer.fromRelativeFile(
        heap.page_allocator,
        test1_path,
        FromFileOptions{ .max_size = 512 },
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
