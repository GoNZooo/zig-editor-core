const file_buffer = @import("./file_buffer.zig");
const FileBuffer = @import("./file_buffer.zig").FileBuffer;
const FileBufferOptions = @import("./file_buffer.zig").FileBufferOptions;
const vim = @import("./vim.zig");

const std = @import("std");
const mem = std.mem;

pub fn BufferState(comptime T: type) type {
    return struct {
        const Self = @This();

        buffer: FileBuffer(T),
        vim_state: vim.State,

        pub fn init(allocator: *mem.Allocator) !Self {
            var buffer = try FileBuffer(T).init(allocator, FileBufferOptions{});

            return Self{
                .buffer = buffer,
                .vim_state = vim.State.start(),
            };
        }
    };
}
