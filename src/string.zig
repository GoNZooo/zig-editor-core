const std = @import("std");
const testing = std.testing;
const ArrayList = std.ArrayList;
const direct_allocator = std.heap.direct_allocator;
const debug = std.debug;
const mem = std.mem;
const fmt = std.fmt;

pub fn StringInitOptions(comptime T: type) type {
    return struct {
        initial_capacity: ?usize = null,
    };
}

pub fn String(comptime T: type) type {
    return struct {
        const Self = @This();
        const Slice = []T;
        const ConstSlice = []const T;

        allocator: *mem.Allocator,
        chars: []T,
        capacity: usize,

        /// Initializes the string, optionally allocating the amount of characters specified as the
        /// `initial_capacity` in `options`.
        /// The caller is responsible for calling `successful_return_value.deinit()`.
        pub fn init(
            allocator: *mem.Allocator,
            options: StringInitOptions(T),
        ) !String(T) {
            const capacity = if (options.initial_capacity) |c| c else 0;
            var chars = if (options.initial_capacity) |c| try allocator.alloc(T, c) else [_]T{};

            return Self{ .chars = chars, .capacity = capacity, .allocator = allocator };
        }

        /// Deinitializes the string, clearing all values inside of it and freeing the memory used.
        pub fn deinit(self: *Self) void {
            self.allocator.free(self.chars);
            self.chars = [_]T{};
            self.capacity = 0;
        }

        /// Copies a const slice of type `T`, meaning this can be used to create a string from a
        /// string literal or other kind of const string value.
        /// The caller is responsible for calling `successful_return_value.deinit()`.
        pub fn copyConst(allocator: *mem.Allocator, slice: ConstSlice) !Self {
            var chars = try mem.dupe(allocator, T, slice);

            return Self{
                .chars = chars,
                .capacity = slice.len,
                .allocator = allocator,
            };
        }

        /// Appends a `[]const T` onto a `String(T)`, mutating the appended to string. The allocator
        /// remains the same as the appended to string and the caller is not the owner of the memory.
        pub fn append(self: *Self, slice: ConstSlice) !void {
            const new_capacity = self.capacity + slice.len;
            var chars = try self.allocator.realloc(self.chars, new_capacity);
            mem.copy(T, chars[self.capacity..], slice);
            self.chars = chars;
            self.capacity = new_capacity;
        }

        /// Appends a `[]const T` onto a `String(T)`, creating a new `String(T)` from it.
        /// The caller is responsible for calling `successful_return_value.deinit()`.
        pub fn appendCopy(self: Self, allocator: *mem.Allocator, slice: ConstSlice) !Self {
            var chars = try mem.concat(allocator, T, [_][]const T{ self.chars, slice });

            return Self{
                .chars = chars,
                .capacity = chars.len,
                .allocator = allocator,
            };
        }

        /// Returns a mutable copy of the contents of the `String(T)`.
        /// The caller is responsible for calling `successful_return_value.deinit()`.
        pub fn sliceCopy(self: Self, allocator: *mem.Allocator) !Slice {
            var chars = try mem.dupe(allocator, T, self.chars);

            return chars;
        }

        /// Returns an immutable copy of the contents of the `String(T)`.
        pub fn sliceConst(self: Self) ConstSlice {
            return self.chars;
        }

        /// Creates a `String(T)` from a format string.
        /// Example: `const string = try fromFormat("{}/{}_{}.txt", dir, filename, version);`
        /// The caller is responsible for calling `successful_return_value.deinit()`.
        pub fn fromFormat(
            allocator: *mem.Allocator,
            comptime format_string: []const u8,
            args: ...,
        ) !Self {
            const chars = try fmt.allocPrint(direct_allocator, format_string, args);
            const capacity = chars.len;
            return Self{ .chars = chars, .capacity = capacity, .allocator = allocator };
        }

        pub fn format(
            self: Self,
            comptime format_string: []const u8,
            options: fmt.FormatOptions,
            context: var,
            comptime Errors: type,
            output: fn (@typeOf(context), []const u8) Errors!void,
        ) Errors!void {
            return fmt.format(context, Errors, output, "{}", self.chars);
        }
    };
}

test "`appendCopy` doesn't disturb original string, `copyConst` copies static strings" {
    var string2 = try String(u8).copyConst(direct_allocator, "hello");
    try string2.append(" there");
    var string3 = try string2.appendCopy(direct_allocator, "wat");

    testing.expectEqualSlices(u8, string2.chars, string3.chars[0..string2.chars.len]);
    testing.expect(&string2.chars[0] != &string3.chars[0]);
    testing.expect(string3.capacity == 14);
    string3.deinit();
    testing.expect(string3.capacity == 0);
    testing.expect(string2.capacity == 11);
}

test "`format` returns a custom format instead of everything" {
    var string2 = try String(u8).copyConst(direct_allocator, "hello");
    var format_output = try fmt.allocPrint(
        direct_allocator,
        "{}! {}!",
        string2,
        @as(u1, 1),
    );

    testing.expectEqualSlices(u8, format_output, "hello! 1!");
}

test "`fromFormat` returns a correct `String`" {
    const username = "gonz";
    const filename = ".zshrc";
    const line = 5;
    const column = 3;
    const string_from_format = try String(u8).fromFormat(
        direct_allocator,
        "/home/{}/{}:{}:{}",
        username,
        filename,
        @as(u8, line),
        @as(u8, column),
    );
    const expected_chars = "/home/gonz/.zshrc:5:3";
    const expected_capacity = expected_chars.len;

    testing.expectEqualSlices(u8, string_from_format.chars, expected_chars);
    testing.expectEqual(string_from_format.capacity, expected_capacity);
    testing.expectEqual(string_from_format.allocator, direct_allocator);
}
