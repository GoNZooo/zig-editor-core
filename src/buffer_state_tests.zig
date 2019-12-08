const BufferState = @import("./buffer_state.zig").BufferState;

const std = @import("std");
const direct_allocator = std.heap.direct_allocator;

test "can create `BufferState`" {
    var buffer_state = try BufferState(u8).init(direct_allocator);
}
