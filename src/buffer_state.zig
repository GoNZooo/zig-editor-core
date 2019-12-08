const file_buffer = @import("./file_buffer.zig");
const FileBuffer = @import("./file_buffer.zig").FileBuffer;
const FileBufferOptions = @import("./file_buffer.zig").FileBufferOptions;
const vim = @import("./vim.zig");

const std = @import("std");
const mem = std.mem;

pub fn BufferState(comptime T: type) type {
    return struct {
        const Self = @This();

        buffer: ?FileBuffer(T),
        vim_state: vim.State,

        pub fn init() Self {
            return Self{
                .buffer = null,
                .vim_state = vim.State.start(),
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.buffer) |*fb| fb.deinit();
        }
    };
}
