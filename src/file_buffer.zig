const std = @import("std");
const mem = std.mem;
const direct_allocator = std.heap.direct_allocator;
const testing = std.testing;
const utilities = @import("./utilities.zig");
const String = @import("./string.zig").String;
const assert = std.debug.assert;

const FileBufferOptions = struct {
    initial_capacity: ?usize = null,
};

const RemoveOptions = struct {
    shrink: bool = false,
};

const AppendCopyOptions = struct {
    shrink: bool = false,
};

const InsertCopyOptions = struct {
    shrink: bool = false,
};

pub fn FileBuffer(comptime T: type) type {
    return struct {
        const Self = @This();
        const Lines = []T;
        const ConstLines = []const T;
        const hasDeinit = @typeInfo(T) == .Struct and @hasDecl(T, "deinit");

        count: usize,
        capacity: usize,
        allocator: *mem.Allocator,
        __lines: []T,

        /// Creates a `FileBuffer`.
        /// The caller is responsible for calling `return_value.deinit()`.
        pub fn init(allocator: *mem.Allocator, options: FileBufferOptions) !Self {
            const capacity = if (options.initial_capacity) |c| c else 0;
            var allocated_lines = try allocator.alloc(T, capacity);

            return Self{
                .__lines = allocated_lines,
                .count = 0,
                .capacity = capacity,
                .allocator = allocator,
            };
        }

        /// Deinitializes the `FileBuffer`, deinitializing all lines inside of it in the process.
        /// If the line stored in the `FileBuffer` has a `deinit()` method, it will be run
        /// automatically.
        pub fn deinit(self: *Self) void {
            if (hasDeinit) (for (self.__lines[0..self.count]) |*l| l.deinit());
            self.allocator.free(self.__lines);
            self.count = 0;
            self.capacity = 0;
            self.__lines = [_]T{};
        }

        // Returns a const slice of the lines in the `FileBuffer`
        pub fn lines(self: Self) ConstLines {
            return self.__lines[0..self.count];
        }

        pub fn append(self: *Self, allocator: *mem.Allocator, lines_to_add: ConstLines) !void {
            const capacity = self.getRequiredCapacity(lines_to_add);
            var allocated_lines = self.__lines;
            if (capacity > self.capacity) {
                allocated_lines = try allocator.realloc(self.__lines, capacity);
            }

            mem.copy(T, allocated_lines[self.count..], lines_to_add);
            self.__lines = allocated_lines;
            self.capacity = capacity;
            self.count += lines_to_add.len;
        }

        pub fn appendCopy(
            self: Self,
            allocator: *mem.Allocator,
            lines_to_add: ConstLines,
            options: AppendCopyOptions,
        ) !Self {
            const capacity = if (options.shrink) (self.count + lines_to_add.len) else self.capacity;
            var allocated_lines = try allocator.alloc(T, capacity);

            mem.copy(T, allocated_lines[self.count..], lines_to_add);

            return Self{
                .capacity = capacity,
                .count = self.count + lines_to_add.len,
                .__lines = allocated_lines,
                .allocator = allocator,
            };
        }

        pub fn insert(self: *Self, start: usize, lines_to_insert: ConstLines) !void {
            const capacity = self.getRequiredCapacity(lines_to_insert);
            const lines_before_start = self.__lines[0..start];
            const start_of_slice_after = start + lines_to_insert.len;
            const end_of_slice_after = self.count + lines_to_insert.len;
            const lines_after_inserted = self.__lines[start..self.count];
            var allocated_lines = self.__lines;
            if (capacity > self.capacity) {
                allocated_lines = try self.allocator.realloc(self.__lines, capacity);
            }

            mem.copy(T, allocated_lines[0..start], lines_before_start);
            mem.copy(
                T,
                allocated_lines[start_of_slice_after..end_of_slice_after],
                lines_after_inserted,
            );
            mem.copy(T, allocated_lines[start..(start + lines_to_insert.len)], lines_to_insert);

            self.__lines = allocated_lines;
            self.capacity = capacity;
            self.count += lines_to_insert.len;
        }

        pub fn insertCopy(
            self: Self,
            allocator: *mem.Allocator,
            start: usize,
            lines_to_insert: ConstLines,
            options: InsertCopyOptions,
        ) !Self {
            const count = self.count + lines_to_insert.len;
            const capacity = if (options.shrink) count else no_shrink: {
                break :no_shrink self.getRequiredCapacity(lines_to_insert);
            };
            const lines_before_start = self.__lines[0..start];
            const start_of_slice_after = start + lines_to_insert.len;
            const end_of_slice_after = self.count + lines_to_insert.len;
            const lines_after_inserted = self.__lines[start..self.count];
            var allocated_lines = try allocator.alloc(T, capacity);

            mem.copy(T, allocated_lines[0..start], lines_before_start);
            mem.copy(
                T,
                allocated_lines[start_of_slice_after..end_of_slice_after],
                lines_after_inserted,
            );
            mem.copy(T, allocated_lines[start..(start + lines_to_insert.len)], lines_to_insert);

            return Self{
                .count = count,
                .capacity = capacity,
                .__lines = allocated_lines,
                .allocator = allocator,
            };
        }

        pub fn remove(self: *Self, start: usize, end: usize, options: RemoveOptions) void {
            assert(start <= end);
            assert(end <= self.count);
            const lines_before_deletion = self.__lines[0..start];
            const lines_after_deletion = self.__lines[end..self.count];
            const count_difference = end - start;
            const count = self.count - count_difference;

            var allocated_lines = self.__lines;
            if (options.shrink) {
                allocated_lines = self.allocator.shrink(self.__lines, count);
                self.capacity = allocated_lines.len;
            }
            for (self.__lines[start..end]) |*removed_line| {
                if (hasDeinit) removed_line.deinit() else self.allocator.free(removed_line.*);
            }

            mem.copy(T, allocated_lines[0..start], lines_before_deletion);
            mem.copy(T, allocated_lines[start..count], lines_after_deletion);
            self.count = count;
            self.capacity = allocated_lines.len;
        }

        pub fn removeCopy(
            self: Self,
            allocator: *mem.Allocator,
            start: usize,
            end: usize,
            options: RemoveOptions,
        ) !Self {
            assert(start <= end);
            assert(end <= self.count);
            const lines_before_deletion = self.__lines[0..start];
            const lines_after_deletion = self.__lines[end..self.count];
            const count_difference = end - start;
            const count = self.count - count_difference;

            var allocated_lines = if (options.shrink) shrink: {
                break :shrink try allocator.alloc(T, count);
            } else no_shrink: {
                break :no_shrink try allocator.alloc(T, self.count);
            };

            mem.copy(T, allocated_lines[0..start], lines_before_deletion);
            mem.copy(T, allocated_lines[start..count], lines_after_deletion);

            return Self{
                .count = count,
                .capacity = allocated_lines.len,
                .__lines = allocated_lines,
                .allocator = allocator,
            };
        }

        fn getRequiredCapacity(self: Self, lines_to_add: ConstLines) usize {
            return utilities.max(usize, self.capacity, self.count + lines_to_add.len);
        }
    };
}

test "`deinit` frees the memory in the `FileBuffer`" {
    var file_buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{});
    testing.expectEqual(file_buffer.count, 0);

    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "there");
    const lines_to_add = ([_]String(u8){ string1, string2 })[0..];
    try file_buffer.append(direct_allocator, lines_to_add);
    const file_buffer_lines = file_buffer.lines();
    const file_buffer_line_1_content = file_buffer_lines[0].__chars;
    testing.expectEqual(file_buffer.count, 2);
    testing.expectEqual(file_buffer.capacity, 2);
    file_buffer.deinit();
}

test "`deinit` frees the memory in the `FileBuffer` without `deinit()` present" {
    var file_buffer = try FileBuffer([]u8).init(direct_allocator, FileBufferOptions{});
    var string1 = try mem.dupe(direct_allocator, u8, "hello"[0..]);
    var string2 = try mem.dupe(direct_allocator, u8, "there"[0..]);
    var string3 = try mem.dupe(direct_allocator, u8, "handsome"[0..]);
    const lines_to_add = ([_][]u8{ string1, string2, string3 })[0..];
    try file_buffer.append(direct_allocator, lines_to_add);
    const file_buffer_lines = file_buffer.lines();
    testing.expectEqual(file_buffer.count, 3);
    testing.expectEqual(file_buffer.capacity, 3);
    file_buffer.deinit();
}

test "`append` appends lines" {
    var file_buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{});
    testing.expectEqual(file_buffer.count, 0);

    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "there");
    const lines_to_add = ([_]String(u8){ string1, string2 })[0..];
    try file_buffer.append(direct_allocator, lines_to_add);

    testing.expectEqual(file_buffer.count, 2);
    testing.expectEqual(file_buffer.capacity, 2);
    for (file_buffer.lines()) |line, i| {
        testing.expectEqualSlices(u8, line.sliceConst(), lines_to_add[i].sliceConst());
        testing.expect(&line != &lines_to_add[i]);
    }
}

test "`append` appends lines but doesn't increase capacity if already sufficient" {
    var file_buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{
        .initial_capacity = 120,
    });
    testing.expectEqual(file_buffer.count, 0);

    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "there");

    const lines_to_add = ([_]String(u8){ string1, string2 })[0..];
    try file_buffer.append(direct_allocator, lines_to_add);
    testing.expectEqual(file_buffer.count, 2);
    testing.expectEqual(file_buffer.capacity, 120);
    for (file_buffer.lines()) |line, i| {
        testing.expectEqualSlices(u8, line.sliceConst(), lines_to_add[i].sliceConst());
    }
}

test "`appendCopy` appends lines" {
    var file_buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{
        .initial_capacity = 120,
    });
    testing.expectEqual(file_buffer.count, 0);

    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "there");

    const lines_to_add = ([_]String(u8){ string1, string2 })[0..];
    var file_buffer2 = try file_buffer.appendCopy(
        direct_allocator,
        lines_to_add,
        AppendCopyOptions{},
    );
    testing.expectEqual(file_buffer2.count, 2);
    testing.expectEqual(file_buffer2.capacity, 120);
    for (file_buffer2.lines()) |line, i| {
        testing.expectEqualSlices(u8, line.sliceConst(), lines_to_add[i].sliceConst());
    }
    testing.expectEqual(file_buffer.count, 0);
    testing.expectEqual(file_buffer.capacity, 120);
}

test "`appendCopy` appends lines and shrinks if given the option" {
    var file_buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{
        .initial_capacity = 120,
    });
    testing.expectEqual(file_buffer.count, 0);

    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "there");

    const lines_to_add = ([_]String(u8){ string1, string2 })[0..];
    var file_buffer2 = try file_buffer.appendCopy(
        direct_allocator,
        lines_to_add,
        AppendCopyOptions{ .shrink = true },
    );
    testing.expectEqual(file_buffer2.count, 2);
    testing.expectEqual(file_buffer2.capacity, 2);
    for (file_buffer2.lines()) |line, i| {
        testing.expectEqualSlices(u8, line.sliceConst(), lines_to_add[i].sliceConst());
    }
    testing.expectEqual(file_buffer.count, 0);
    testing.expectEqual(file_buffer.capacity, 120);
}

test "`insert` inserts lines" {
    var file_buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{});
    testing.expectEqual(file_buffer.count, 0);

    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "you");
    const string3 = try String(u8).copyConst(direct_allocator, "!");
    const lines_to_add = ([_]String(u8){ string1, string2, string3 })[0..];
    try file_buffer.append(direct_allocator, lines_to_add);
    const string4 = try String(u8).copyConst(direct_allocator, "there,");
    const string5 = try String(u8).copyConst(direct_allocator, "you");
    const string6 = try String(u8).copyConst(direct_allocator, "handsome");
    const string7 = try String(u8).copyConst(direct_allocator, "devil");
    const lines_to_insert = ([_]String(u8){ string4, string5, string6, string7 })[0..];
    try file_buffer.insert(1, lines_to_insert);
    testing.expectEqual(file_buffer.count, 7);
    testing.expectEqual(file_buffer.capacity, 7);
    testing.expectEqualSlices(u8, file_buffer.lines()[0].sliceConst(), "hello");
    testing.expectEqualSlices(u8, file_buffer.lines()[1].sliceConst(), "there,");
    testing.expectEqualSlices(u8, file_buffer.lines()[2].sliceConst(), "you");
    testing.expectEqualSlices(u8, file_buffer.lines()[3].sliceConst(), "handsome");
    testing.expectEqualSlices(u8, file_buffer.lines()[4].sliceConst(), "devil");
    testing.expectEqualSlices(u8, file_buffer.lines()[5].sliceConst(), "you");
    testing.expectEqualSlices(u8, file_buffer.lines()[6].sliceConst(), "!");
}

test "`insertCopy` inserts lines" {
    var file_buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{});
    testing.expectEqual(file_buffer.count, 0);

    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "you");
    const string3 = try String(u8).copyConst(direct_allocator, "!");
    const lines_to_add = ([_]String(u8){ string1, string2, string3 })[0..];
    try file_buffer.append(direct_allocator, lines_to_add);
    const string4 = try String(u8).copyConst(direct_allocator, "there,");
    const string5 = try String(u8).copyConst(direct_allocator, "you");
    const string6 = try String(u8).copyConst(direct_allocator, "handsome");
    const string7 = try String(u8).copyConst(direct_allocator, "devil");
    const lines_to_insert = ([_]String(u8){ string4, string5, string6, string7 })[0..];
    var file_buffer2 = try file_buffer.insertCopy(
        direct_allocator,
        1,
        lines_to_insert,
        InsertCopyOptions{},
    );
    testing.expectEqual(file_buffer2.count, 7);
    testing.expectEqual(file_buffer2.capacity, 7);
    testing.expectEqualSlices(u8, file_buffer2.lines()[0].sliceConst(), "hello");
    testing.expectEqualSlices(u8, file_buffer2.lines()[1].sliceConst(), "there,");
    testing.expectEqualSlices(u8, file_buffer2.lines()[2].sliceConst(), "you");
    testing.expectEqualSlices(u8, file_buffer2.lines()[3].sliceConst(), "handsome");
    testing.expectEqualSlices(u8, file_buffer2.lines()[4].sliceConst(), "devil");
    testing.expectEqualSlices(u8, file_buffer2.lines()[5].sliceConst(), "you");
    testing.expectEqualSlices(u8, file_buffer2.lines()[6].sliceConst(), "!");
}

test "`insertCopy` inserts lines and doesn't shrink unless told otherwise" {
    var file_buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{
        .initial_capacity = 80,
    });
    testing.expectEqual(file_buffer.count, 0);
    testing.expectEqual(file_buffer.capacity, 80);

    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "you");
    const string3 = try String(u8).copyConst(direct_allocator, "!");
    const lines_to_add = ([_]String(u8){ string1, string2, string3 })[0..];
    try file_buffer.append(direct_allocator, lines_to_add);
    const string4 = try String(u8).copyConst(direct_allocator, "there,");
    const string5 = try String(u8).copyConst(direct_allocator, "you");
    const string6 = try String(u8).copyConst(direct_allocator, "handsome");
    const string7 = try String(u8).copyConst(direct_allocator, "devil");
    const lines_to_insert = ([_]String(u8){ string4, string5, string6, string7 })[0..];
    var file_buffer2 = try file_buffer.insertCopy(
        direct_allocator,
        1,
        lines_to_insert,
        InsertCopyOptions{},
    );
    testing.expectEqual(file_buffer2.count, 7);
    testing.expectEqual(file_buffer2.capacity, 80);
    testing.expectEqualSlices(u8, file_buffer2.lines()[0].sliceConst(), "hello");
    testing.expectEqualSlices(u8, file_buffer2.lines()[1].sliceConst(), "there,");
    testing.expectEqualSlices(u8, file_buffer2.lines()[2].sliceConst(), "you");
    testing.expectEqualSlices(u8, file_buffer2.lines()[3].sliceConst(), "handsome");
    testing.expectEqualSlices(u8, file_buffer2.lines()[4].sliceConst(), "devil");
    testing.expectEqualSlices(u8, file_buffer2.lines()[5].sliceConst(), "you");
    testing.expectEqualSlices(u8, file_buffer2.lines()[6].sliceConst(), "!");
}

test "`insertCopy` inserts lines and shrinks if told to do so" {
    var file_buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{
        .initial_capacity = 80,
    });
    testing.expectEqual(file_buffer.count, 0);
    testing.expectEqual(file_buffer.capacity, 80);

    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "you");
    const string3 = try String(u8).copyConst(direct_allocator, "!");
    const lines_to_add = ([_]String(u8){ string1, string2, string3 })[0..];
    try file_buffer.append(direct_allocator, lines_to_add);
    const string4 = try String(u8).copyConst(direct_allocator, "there,");
    const string5 = try String(u8).copyConst(direct_allocator, "you");
    const string6 = try String(u8).copyConst(direct_allocator, "handsome");
    const string7 = try String(u8).copyConst(direct_allocator, "devil");
    const lines_to_insert = ([_]String(u8){ string4, string5, string6, string7 })[0..];
    var file_buffer2 = try file_buffer.insertCopy(direct_allocator, 1, lines_to_insert, InsertCopyOptions{
        .shrink = true,
    });
    testing.expectEqual(file_buffer2.count, 7);
    testing.expectEqual(file_buffer2.capacity, 7);
    testing.expectEqualSlices(u8, file_buffer2.lines()[0].sliceConst(), "hello");
    testing.expectEqualSlices(u8, file_buffer2.lines()[1].sliceConst(), "there,");
    testing.expectEqualSlices(u8, file_buffer2.lines()[2].sliceConst(), "you");
    testing.expectEqualSlices(u8, file_buffer2.lines()[3].sliceConst(), "handsome");
    testing.expectEqualSlices(u8, file_buffer2.lines()[4].sliceConst(), "devil");
    testing.expectEqualSlices(u8, file_buffer2.lines()[5].sliceConst(), "you");
    testing.expectEqualSlices(u8, file_buffer2.lines()[6].sliceConst(), "!");
}

test "`remove` removes" {
    var file_buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{});
    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "there");
    const string3 = try String(u8).copyConst(direct_allocator, "handsome");
    const lines_to_add = ([_]String(u8){ string1, string2, string3 })[0..];
    try file_buffer.append(direct_allocator, lines_to_add);
    file_buffer.remove(1, 2, RemoveOptions{});
    testing.expectEqual(file_buffer.capacity, 3);
    testing.expectEqual(file_buffer.count, 2);
    testing.expectEqualSlices(u8, file_buffer.lines()[0].sliceConst(), string1.sliceConst());
    testing.expectEqualSlices(u8, file_buffer.lines()[1].sliceConst(), string3.sliceConst());
}

test "`remove` removes and shrinks when `shrink` option is `true`" {
    var file_buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{});
    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "there");
    const string3 = try String(u8).copyConst(direct_allocator, "handsome");
    const lines_to_add = ([_]String(u8){ string1, string2, string3 })[0..];
    try file_buffer.append(direct_allocator, lines_to_add);
    file_buffer.remove(1, 2, RemoveOptions{ .shrink = true });
    testing.expectEqual(file_buffer.capacity, 2);
    testing.expectEqual(file_buffer.count, 2);
    testing.expectEqualSlices(u8, file_buffer.lines()[0].sliceConst(), string1.sliceConst());
    testing.expectEqualSlices(u8, file_buffer.lines()[1].sliceConst(), string3.sliceConst());
}

test "`remove` removes when type does not have `deinit()`" {
    var file_buffer = try FileBuffer([]u8).init(direct_allocator, FileBufferOptions{});
    var string1 = try mem.dupe(direct_allocator, u8, "hello"[0..]);
    var string2 = try mem.dupe(direct_allocator, u8, "there"[0..]);
    var string3 = try mem.dupe(direct_allocator, u8, "handsome"[0..]);
    const lines_to_add = ([_][]u8{ string1, string2, string3 })[0..];
    try file_buffer.append(direct_allocator, lines_to_add);
    file_buffer.remove(1, 2, RemoveOptions{});
    testing.expectEqual(file_buffer.capacity, 3);
    testing.expectEqual(file_buffer.count, 2);
    testing.expectEqualSlices(u8, file_buffer.lines()[0], string1);
    testing.expectEqualSlices(u8, file_buffer.lines()[1], string3);
}

test "`removeCopy` removes and gives a new `FileBuffer`" {
    var file_buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{});
    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "there");
    const string3 = try String(u8).copyConst(direct_allocator, "handsome");
    const lines_to_add = ([_]String(u8){ string1, string2, string3 })[0..];
    try file_buffer.append(direct_allocator, lines_to_add);
    var file_buffer2 = try file_buffer.removeCopy(direct_allocator, 1, 2, RemoveOptions{});
    testing.expectEqual(file_buffer2.capacity, 3);
    testing.expectEqual(file_buffer2.count, 2);
    testing.expectEqualSlices(u8, file_buffer2.lines()[0].sliceConst(), string1.sliceConst());
    testing.expectEqualSlices(u8, file_buffer2.lines()[1].sliceConst(), string3.sliceConst());
}

test "`removeCopy` removes and gives a new `FileBuffer` and can shrink" {
    var file_buffer = try FileBuffer(String(u8)).init(direct_allocator, FileBufferOptions{});
    const string1 = try String(u8).copyConst(direct_allocator, "hello");
    const string2 = try String(u8).copyConst(direct_allocator, "there");
    const string3 = try String(u8).copyConst(direct_allocator, "handsome");
    const lines_to_add = ([_]String(u8){ string1, string2, string3 })[0..];
    try file_buffer.append(direct_allocator, lines_to_add);
    var file_buffer2 = try file_buffer.removeCopy(direct_allocator, 1, 2, RemoveOptions{
        .shrink = true,
    });
    testing.expectEqual(file_buffer2.capacity, 2);
    testing.expectEqual(file_buffer2.count, 2);
    testing.expectEqualSlices(u8, file_buffer2.lines()[0].sliceConst(), string1.sliceConst());
    testing.expectEqualSlices(u8, file_buffer2.lines()[1].sliceConst(), string3.sliceConst());
}

pub fn runTests() void {}
