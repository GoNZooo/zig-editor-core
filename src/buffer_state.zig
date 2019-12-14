const file_buffer = @import("./file_buffer.zig");
const FileBuffer = @import("./file_buffer.zig").FileBuffer;
const FileBufferOptions = @import("./file_buffer.zig").FileBufferOptions;
const FromFileOptions = @import("./file_buffer.zig").FromFileOptions;
const vim = @import("./vim.zig");
const String = @import("./string.zig").String;

const std = @import("std");
const mem = std.mem;

const Cursor = struct {
    column: u32,
    line: u32,
};

pub const BufferStateOptions = struct {
    pathToRelativeFile: ?[]const u8 = null,
    from_file_options: ?FromFileOptions = null,
};

/// Is meant to represent the state of a buffer, which loosely should mean a view into a file.
/// That file does not need to exist on disk, but is rather just a collection of text.
pub fn BufferState(comptime T: type, comptime tFromU8: file_buffer.TFromU8Function(T)) type {
    return struct {
        const Self = @This();

        buffer: FileBuffer(T, tFromU8),
        vim_state: vim.State,
        cursor: Cursor,
        allocator: *mem.Allocator,

        pub fn init(
            allocator: *mem.Allocator,
            options: BufferStateOptions,
            file_buffer_options: FileBufferOptions,
        ) !Self {
            var buffer: FileBuffer(T, tFromU8) = undefined;
            if (options.pathToRelativeFile) |path| {
                const ff_options = if (options.from_file_options) |o| o else FromFileOptions{
                    .max_size = 256,
                };
                buffer = try FileBuffer(T, tFromU8).fromRelativeFile(
                    allocator,
                    path,
                    ff_options,
                    FileBufferOptions{},
                );
            } else {
                buffer = try FileBuffer(T, tFromU8).init(allocator, file_buffer_options);
            }

            return Self{
                .buffer = buffer,
                .vim_state = vim.State.start(),
                .cursor = Cursor{ .column = 0, .line = 0 },
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.buffer.deinit();
        }

        // from_file_options: FromFileOptions,
        // file_buffer_options: FileBufferOptions,
        pub fn loadRelativeFile(
            self: *Self,
            allocator: *mem.Allocator,
            path: []const u8,
            from_file_options: FromFileOptions,
        ) !void {
            var buffer = try FileBuffer(T, tFromU8).fromRelativeFile(
                allocator,
                path,
                from_file_options,
                FileBufferOptions{},
            );
            self.buffer = buffer;
        }

        pub fn setCursor(self: *Self, cursor: Cursor) void {
            self.cursor = cursor;
        }

        pub fn handleKey(self: *Self, key: vim.Key) !void {
            if (try vim.handleKey(self.allocator, key, &self.vim_state)) |command| {
                switch (command) {
                    .MotionOnly => |command_data| {
                        self.handleMotion(command_data.motion);
                    },
                    .Unset, .Undo, .Redo, .EnterInsertMode, .ExitInsertMode => unreachable,
                    .BeginMacro, .EndMacro => unreachable,
                    .InsertUpwards, .InsertDownwards, .ReplaceInsert, .Insert => unreachable,
                    .Delete, .Yank, .Change => unreachable,
                    .PasteForwards, .PasteBackwards, .SetMark, .Comment => unreachable,
                    .ScrollTop, .ScrollCenter, .ScrollBottom, .BringLineUp => unreachable,
                }
            }
        }

        fn handleMotion(self: *Self, motion: vim.Motion) void {
            switch (motion) {
                .UntilNextWord => |range| {
                    var i: u32 = 0;
                    while (i < range) : (i += 1) {
                        self.cursor = findNextWord(self.cursor, self.buffer);
                    }
                },
                else => unreachable,
            }
        }

        fn findNextWord(cursor: Cursor, buffer: FileBuffer(T, tFromU8)) Cursor {
            if (buffer.lines()[cursor.line].isEmpty()) {
                return Cursor{ .line = cursor.line + 1, .column = 0 };
            }

            var column = cursor.column;

            const starting_character = buffer.lines()[cursor.line].sliceConst()[cursor.column];
            var seen_space = !(starting_character != ' ');
            var seen_non_word_character = nonWordCharacter(starting_character);

            for (buffer.lines()[cursor.line..]) |l, line| {
                if (l.isEmpty()) {
                    return Cursor{
                        .line = @intCast(u32, line + cursor.line),
                        .column = 0,
                    };
                }

                for (l.sliceConst()[column..]) |c| {
                    if (seen_space and c != ' ') {
                        return Cursor{
                            .line = @intCast(u32, line + cursor.line),
                            .column = @intCast(u32, column),
                        };
                    }
                    if (nonWordCharacter(c) and !seen_non_word_character) {
                        return Cursor{
                            .line = @intCast(u32, line + cursor.line),
                            .column = @intCast(u32, column),
                        };
                    }
                    if (c == ' ') seen_space = true;
                    column += 1;
                }

                // we've reached the end of a line; newline counts as having seen a space here
                seen_space = true;
                column = 0;
            }

            // if we couldn't actually find a result, just return the cursor we had
            return cursor;
        }
    };
}

fn nonWordCharacter(c: u8) bool {
    return switch (c) {
        ',', '.', '-', '(', ')', '/' => true,
        else => false,
    };
}
