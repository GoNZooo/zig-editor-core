pub const TestAllocator = @import("std").heap.GeneralPurposeAllocator(.{});

pub fn checkLeakCount(allocator: *TestAllocator) !void {
    return if (allocator.detectLeaks()) error.LeakDetected;
}
