const std = @import("std");
const testing = std.testing;
const direct_allocator = std.heap.direct_allocator;
const mem = std.mem;
const fmt = std.fmt;
const rand = std.rand;
const assert = std.debug.assert;

pub const StringInitOptions = struct {
    initial_capacity: ?usize = null,
};

pub const DeleteOptions = struct {
    shrink: bool = false,
};

pub fn String(comptime T: type) type {
    // @TODO: Figure out if a way of calculating new capacity is general enough where it should be
    // the default instead of "only what's needed". Alternatively, create different modes, i.e.;
    // `.Eager`: Eagerly allocates more space for more characters to be added. Some constant here?
    // `.Strict`: Allocates strictly what's necessary.
    // `.Bracketed([]u32)`(?):
    //     Set up different key brackets that are allocated up to, with fallback constant value for
    //     when we enter non-bracketed territory.
    return struct {
        const Self = @This();
        const Slice = []T;
        const ConstSlice = []const T;

        allocator: *mem.Allocator,
        capacity: usize,
        count: usize,

        // @NOTE: Regard as private
        __chars: []T,

        /// Initializes the string, optionally allocating the amount of characters specified as the
        /// `initial_capacity` in `options`.
        /// The caller is responsible for calling `successful_return_value.deinit()`.
        pub fn init(
            allocator: *mem.Allocator,
            options: StringInitOptions,
        ) !String(T) {
            const capacity = if (options.initial_capacity) |c| c else 0;
            var chars = try allocator.alloc(T, capacity);

            return Self{
                .__chars = chars,
                .capacity = capacity,
                .allocator = allocator,
                .count = 0,
            };
        }

        /// Deinitializes the string, clearing all values inside of it and freeing the memory used.
        pub fn deinit(self: *Self) void {
            // @TODO: Determine whether or not it's better to have invalid memory here so that it
            // can be caught, instead of producing a valid empty slice.
            self.allocator.free(self.__chars);
            self.__chars = [_]T{};
            self.capacity = 0;
            self.count = 0;
        }

        /// Copies a const slice of type `T`, meaning this can be used to create a string from a
        /// string literal or other kind of const string value.
        /// The caller is responsible for calling `successful_return_value.deinit()`.
        pub fn copyConst(allocator: *mem.Allocator, slice: ConstSlice) !Self {
            var chars = try mem.dupe(allocator, T, slice);

            return Self{
                .__chars = chars,
                .capacity = slice.len,
                .allocator = allocator,
                .count = slice.len,
            };
        }

        /// Appends a `[]const T` onto a `String(T)`, mutating the appended to string. The allocator
        /// remains the same as the appended to string and the caller is not the owner of the memory.
        /// If the current capacity of the string is enough to hold the new string no new memory
        /// will be allocated.
        pub fn append(self: *Self, slice: ConstSlice) !void {
            const new_capacity = self.getNewCapacity(slice);
            var chars = self.__chars;
            if (new_capacity > self.capacity) {
                chars = try self.allocator.realloc(self.__chars, new_capacity);
            }
            mem.copy(T, chars[self.count..], slice);
            self.__chars = chars;
            self.capacity = new_capacity;
            self.count = self.count + slice.len;
        }

        /// Appends a `[]const T` onto a `String(T)`, creating a new `String(T)` from it. The copy
        /// will ignore the capacity of the original string.
        /// The caller is responsible for calling `successful_return_value.deinit()`.
        pub fn appendCopy(self: Self, allocator: *mem.Allocator, slice: ConstSlice) !Self {
            var chars = try mem.concat(
                allocator,
                T,
                [_][]const T{ self.__chars[0..self.count], slice },
            );

            return Self{
                .__chars = chars,
                .capacity = chars.len,
                .allocator = allocator,
                .count = chars.len,
            };
        }

        /// Copies the contents of `slice` into the `String` at `position` (0-indexed).
        /// Since this modifies an already existing string the responsibility of freeing memory
        /// still lies in the user of the `String`.
        pub fn insertSlice(self: *Self, position: usize, slice: ConstSlice) !void {
            const new_capacity = self.getNewCapacity(slice);
            var characters = self.__chars;
            if (new_capacity > self.capacity) {
                characters = try self.allocator.realloc(characters, new_capacity);
            }
            const slice_to_copy_forward = characters[position..self.count];
            const new_start_position = position + slice.len;
            mem.copy(
                T,
                characters[new_start_position..(new_start_position + slice_to_copy_forward.len)],
                slice_to_copy_forward,
            );
            mem.copy(T, characters[position..(position + slice.len)], slice);

            self.capacity = new_capacity;
            self.count += slice.len;
            self.__chars = characters;
        }

        /// Copies the contents of `slice` into a copy of `String` at `position` (0-indexed).
        /// The caller is responsible for calling `successful_return_value.deinit()`.
        pub fn insertSliceCopy(
            self: Self,
            allocator: *mem.Allocator,
            position: usize,
            slice: ConstSlice,
        ) !Self {
            const capacity = self.count + slice.len;
            var characters = try allocator.alloc(T, self.count + slice.len);
            const slice_to_copy_forward = self.__chars[position..self.count];
            const new_start_position = position + slice.len;
            mem.copy(T, characters[0..position], self.__chars[0..position]);
            mem.copy(
                T,
                characters[new_start_position..(new_start_position + slice_to_copy_forward.len)],
                slice_to_copy_forward,
            );
            mem.copy(
                T,
                characters[position..(position + slice.len)],
                slice,
            );

            return Self{
                .__chars = characters,
                .capacity = capacity,
                .count = characters.len,
                .allocator = allocator,
            };
        }

        /// Deletes a slice inside the string, from `start` to but not including `end` (0-indexed).
        /// The memory is conditionally shrunk based on the `shrink` member in `options` being
        /// `true` or `false.
        pub fn delete(self: *Self, start: usize, end: usize, options: DeleteOptions) void {
            // determine the slice
            const slice_to_remove = self.__chars[start..end];

            // move what's after the slice (end of slice <-> end of string) to where slice starts
            const slice_after_removed_space = self.__chars[end..self.count];
            mem.copy(T, self.__chars[start..self.count], slice_after_removed_space);

            // determine the new count based on the removed slice (count - slice size)
            const count = self.count - slice_to_remove.len;

            // conditionally shrink the memory down to that count
            if (options.shrink) {
                self.__chars = self.allocator.shrink(self.__chars, count);
                self.capacity = count;
            }
            self.count = count;
        }

        /// Deletes a slice inside the string, from `start` to but not including `end` (0-indexed)
        /// and returns a new `String`.
        /// The caller is responsible for calling `successful_return_value.deinit()`.
        pub fn deleteCopy(self: Self, allocator: *mem.Allocator, start: usize, end: usize) !Self {
            assert(start <= end);
            const slice_to_remove = self.__chars[start..end];
            const slice_after_removed_space = self.__chars[end..self.count];
            var characters = try allocator.alloc(T, self.count - slice_to_remove.len);

            mem.copy(T, characters[0..start], self.__chars[0..start]);
            mem.copy(T, characters[start..], slice_after_removed_space);

            return Self{
                .__chars = characters,
                .count = characters.len,
                .capacity = characters.len,
                .allocator = allocator,
            };
        }

        /// Returns a mutable copy of the contents of the `String(T)`.
        /// caller is responsible for calling `successful_return_value.deinit()`.
        pub fn sliceCopy(self: Self, allocator: *mem.Allocator) !Slice {
            var chars = try mem.dupe(allocator, T, self.__chars[0..self.count]);

            return chars;
        }

        /// Returns an immutable copy of the contents of the `String(T)`.
        pub fn sliceConst(self: Self) ConstSlice {
            return self.__chars[0..self.count];
        }

        /// Creates a `String(T)` from a format string.
        /// Example:
        /// ```
        /// const string = try String(u8).fromFormat("{}/{}_{}.txt", dir, filename, version);
        /// ```
        /// The caller is responsible for calling `successful_return_value.deinit()`.
        pub fn fromFormat(
            allocator: *mem.Allocator,
            comptime format_string: []const u8,
            args: ...,
        ) !Self {
            const chars = try fmt.allocPrint(direct_allocator, format_string, args);
            const capacity = chars.len;
            return Self{
                .__chars = chars,
                .capacity = capacity,
                .allocator = allocator,
                .count = chars.len,
            };
        }

        /// Creates a `String(T)` with random content. A `rand.Random` struct can be passed into as
        /// an `option` in order to use a pre-initialized `Random`.
        /// The caller is responsible for calling `successful_return_value.deinit()`.
        pub fn random(allocator: *mem.Allocator, options: RandomSliceOptions) !Self {
            // @TODO: fix this for at least u16 or something
            if (T != u8) @compileError("`.random()` only works with u8 `String`s for now");

            var slice = try randomU8Slice(allocator, options);
            const capacity = slice.len;
            const count = slice.len;

            return Self{
                .__chars = slice,
                .capacity = capacity,
                .count = count,
                .allocator = allocator,
            };
        }

        pub fn format(
            self: Self,
            comptime format_string: []const u8,
            options: fmt.FormatOptions,
            context: var,
            comptime Errors: type,
            output: fn (@typeOf(context), []const u8) Errors!void,
        ) Errors!void {
            return fmt.format(context, Errors, output, "{}", self.__chars[0..self.count]);
        }

        fn getNewCapacity(self: Self, slice: ConstSlice) usize {
            return max(@typeOf(self.capacity), self.capacity, self.count + slice.len);
        }
    };
}

test "`append` with an already high enough capacity doesn't change capacity" {
    const initial_capacity = 80;
    var string = try String(u8).init(direct_allocator, StringInitOptions{
        .initial_capacity = initial_capacity,
    });

    testing.expectEqual(string.count, 0);
    testing.expectEqual(string.capacity, initial_capacity);

    const added_slice = "hello";
    try string.append(added_slice);
    testing.expectEqual(string.capacity, initial_capacity);
    testing.expectEqual(string.count, added_slice.len);
}

test "`appendCopy` doesn't bring unused space with it" {
    const initial_capacity = 80;
    var string = try String(u8).init(direct_allocator, StringInitOptions{
        .initial_capacity = initial_capacity,
    });

    testing.expectEqual(string.count, 0);
    testing.expectEqual(string.capacity, initial_capacity);

    const added_slice = "hello";
    const string2 = try string.appendCopy(direct_allocator, added_slice);
    testing.expectEqual(string2.capacity, added_slice.len);
    testing.expectEqual(string2.count, added_slice.len);
    testing.expectEqualSlices(u8, string2.sliceConst(), added_slice);
}

test "`appendCopy` doesn't disturb original string, `copyConst` copies static strings" {
    var string2 = try String(u8).copyConst(direct_allocator, "hello");
    try string2.append(" there");
    var string3 = try string2.appendCopy(direct_allocator, "wat");

    testing.expectEqualSlices(
        u8,
        string2.sliceConst(),
        string3.__chars[0..string2.sliceConst().len],
    );
    testing.expectEqualSlices(u8, string2.sliceConst(), "hello there");
    testing.expect(&string2.sliceConst()[0] != &string3.sliceConst()[0]);
    testing.expect(string3.capacity == 14);
    string3.deinit();
    testing.expect(string3.capacity == 0);
    testing.expect(string2.capacity == 11);
}

test "`insertSlice` inserts a string into an already created string" {
    var string = try String(u8).copyConst(direct_allocator, "hello!");
    try string.insertSlice(5, "lo");
    testing.expectEqualSlices(u8, string.sliceConst(), "hellolo!");
    try string.insertSlice(5, ", bo");
    testing.expectEqualSlices(u8, string.sliceConst(), "hello, bolo!");
}

test "`insertSliceCopy` inserts a string into a copy of a `String`" {
    var string = try String(u8).copyConst(direct_allocator, "hello!");
    const string2 = try string.insertSliceCopy(direct_allocator, 5, "lo");
    testing.expectEqualSlices(u8, string2.sliceConst(), "hellolo!");
    const string3 = try string2.insertSliceCopy(direct_allocator, 5, ", bo");
    testing.expectEqualSlices(u8, string3.sliceConst(), "hello, bolo!");
}

test "`delete` deletes" {
    var string = try String(u8).copyConst(direct_allocator, "hello!");
    string.delete(1, 4, DeleteOptions{});
    testing.expectEqualSlices(u8, string.sliceConst(), "ho!");
    testing.expectEqual(string.capacity, 6);
}

test "`delete` deletes and shrinks if given the option" {
    var string = try String(u8).copyConst(direct_allocator, "hello!");
    string.delete(1, 4, DeleteOptions{ .shrink = true });
    testing.expectEqualSlices(u8, string.sliceConst(), "ho!");
    testing.expectEqual(string.capacity, 3);
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

test "`deleteCopy` deletes" {
    var string = try String(u8).copyConst(direct_allocator, "hello, bolo!");
    const string2 = try string.deleteCopy(direct_allocator, 1, 4);
    testing.expectEqualSlices(u8, string2.sliceConst(), "ho, bolo!");
    testing.expectEqual(string2.capacity, 9);

    const string3 = try string2.deleteCopy(direct_allocator, 2, 8);
    testing.expectEqualSlices(u8, string3.sliceConst(), "ho!");
    testing.expectEqual(string3.capacity, 3);
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
    const expected_slice = "/home/gonz/.zshrc:5:3";
    const expected_capacity = expected_slice.len;

    testing.expectEqualSlices(u8, string_from_format.sliceConst(), expected_slice);
    testing.expectEqual(string_from_format.capacity, expected_capacity);
    testing.expectEqual(string_from_format.allocator, direct_allocator);
}

test "`random` works" {
    const string = try String(u8).random(direct_allocator, RandomSliceOptions{});
    const slice = string.sliceConst();
    testing.expect(slice.len < 251);
    for (slice) |c| {
        testing.expect(c <= 255);
    }
}

// This probably exists somewhere but I'm not wasting time looking for it
fn max(comptime T: type, a: T, b: T) T {
    return if (a > b) a else b;
}

test "`randomU8Slice`" {
    const slice = try randomU8Slice(direct_allocator, RandomSliceOptions{});
    testing.expect(slice.len < 251);
    for (slice) |c| {
        testing.expect(c <= 255);
    }
}

pub const RandomSliceOptions = struct {
    length: ?usize = null,
    random: ?*rand.Random = null,
};

fn randomU8Slice(
    allocator: *mem.Allocator,
    options: RandomSliceOptions,
) ![]u8 {
    var random = if (options.random) |r| r else blk: {
        var buf: [8]u8 = undefined;
        try std.crypto.randomBytes(buf[0..]);
        const seed = mem.readIntSliceLittle(u64, buf[0..8]);
        break :blk &rand.DefaultPrng.init(seed).random;
    };
    const length = if (options.length) |l| l else random.uintAtMost(usize, 250);
    var slice_characters = try allocator.alloc(u8, length);
    for (slice_characters) |*c| {
        c.* = random.uintAtMost(u8, 255);
    }

    return slice_characters;
}
