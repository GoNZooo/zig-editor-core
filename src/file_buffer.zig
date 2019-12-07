const std = @import("std");
const mem = std.mem;
const direct_allocator = std.heap.direct_allocator;
const testing = std.testing;
const utilities = @import("./utilities.zig");
const String = @import("./string.zig").String;
const assert = std.debug.assert;

pub const FileBufferOptions = struct {
    initial_capacity: ?usize = null,
};

pub const RemoveOptions = struct {
    shrink: bool = false,
};

pub const AppendCopyOptions = struct {
    shrink: bool = false,
};

pub const InsertCopyOptions = struct {
    shrink: bool = false,
};

pub const FromFileOptions = struct {
    newline_delimiter: ?[]const u8 = null,
    max_size: usize,
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

        /// De-initializes the `FileBuffer`, de-initializing all lines inside of it in the process.
        /// If the line stored in the `FileBuffer` has a `deinit()` method, it will be run
        /// automatically.
        pub fn deinit(self: *Self) void {
            if (hasDeinit) (for (self.__lines[0..self.count]) |*l| l.deinit());
            self.allocator.free(self.__lines);
            self.count = 0;
            self.capacity = 0;
            self.__lines = &[_]T{};
        }

        /// Creates a `FileBuffer` from a file. The created `FileBuffer` will be created with the
        /// `FileBufferOptions` passed, allowing for the usual initialization to be done.
        /// A maximum size for the file has to be given via the `FromFileOptions` struct and a
        /// `.newline_delimiter` can be specified. If not specified, will default to the targeted
        /// platform.
        pub fn fromRelativeFile(
            allocator: *mem.Allocator,
            filename: []const u8,
            from_file_options: FromFileOptions,
            file_buffer_options: FileBufferOptions,
        ) !Self {
            const newline_delimiter = if (from_file_options.newline_delimiter) |d| d else default: {
                break :default getPlatformNewlineDelimiter();
            };

            var cwd = std.fs.cwd();
            var file_bytes = try cwd.readFileAlloc(allocator, filename, from_file_options.max_size);
            var newline_iterator = mem.separate(file_bytes, newline_delimiter);
            var buffer = try Self.init(allocator, file_buffer_options);
            while (newline_iterator.next()) |l| {
                try buffer.addLine(allocator, try String(u8).copyConst(allocator, l));
            }

            return buffer;
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

        pub fn addLine(self: *Self, allocator: *mem.Allocator, line: T) !void {
            try self.append(allocator, &[_]T{line});
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
fn getPlatformNewlineDelimiter() []const u8 {
    return switch (std.builtin.os) {
        .windows => "\r\n",
        // @TODO: establish if `else` here is actually representative of reality.
        else => "\n",
    };
}
