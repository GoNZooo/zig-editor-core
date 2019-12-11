const file_buffer = @import("./file_buffer.zig");
const FileBuffer = @import("./file_buffer.zig").FileBuffer;
const FileBufferOptions = @import("./file_buffer.zig").FileBufferOptions;
const FromFileOptions = @import("./file_buffer.zig").FromFileOptions;
const vim = @import("./vim.zig");
const String = @import("./string.zig").String;

const std = @import("std");
const mem = std.mem;

const CursorPosition = struct {
    column: u32,
    line: u32,
};

/// Is meant to represent the state of a buffer, which loosely should mean a given view into a file.
/// That file does not need to exist on disk, but is rather just a collection of text.
pub fn BufferState(comptime T: type, comptime tFromU8: file_buffer.TFromU8Function(T)) type {
    return struct {
        const Self = @This();

        buffer: FileBuffer(T, tFromU8),
        vim_state: vim.State,
        cursor: CursorPosition,

        pub fn init(allocator: *mem.Allocator, file_buffer_options: FileBufferOptions) !Self {
            var buffer = try FileBuffer(T, tFromU8).init(allocator, file_buffer_options);

            return Self{
                .buffer = buffer,
                .vim_state = vim.State.start(),
                .cursor = CursorPosition{ .column = 0, .line = 0 },
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
    };
}
