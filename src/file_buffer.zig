const std = @import("std");
const mem = std.mem;
const direct_allocator = std.heap.direct_allocator;
const testing = std.testing;
const utilities = @import("./utilities.zig");
const String = @import("./string.zig").String;

const FileBufferOptions = struct {
    initial_capacity: ?usize = null,
};

pub fn FileBuffer(comptime T: type) type {
    return struct {
        const Self = @This();
        const Lines = []T;
        const ConstLines = []const T;

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

        // @TODO: add `appendCopy`

        fn getRequiredCapacity(self: Self, lines_to_add: ConstLines) usize {
            return utilities.max(usize, self.capacity, self.count + lines_to_add.len);
        }
    };
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

pub fn runTests() void {}
