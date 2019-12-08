const BufferState = @import("./buffer_state.zig").BufferState;

const std = @import("std");
const direct_allocator = std.heap.direct_allocator;
const testing = std.testing;
const meta = std.meta;

test "`init` works" {
    var buffer_state = try BufferState(u8).init(direct_allocator);
    testing.expect(meta.activeTag(buffer_state.vim_state) == .Start);
}

test "`deinit` works" {
    var buffer_state = try BufferState(u8).init(direct_allocator);
    buffer_state.deinit();
}
