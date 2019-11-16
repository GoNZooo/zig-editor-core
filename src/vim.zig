const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const direct_allocator = std.heap.direct_allocator;
const ArrayList = std.ArrayList;

pub fn runTests() void {}

pub const Motion = union(enum) {
    Unset,
    NoMotion,
    UntilEndOfWord,
    UntilNextWord,
    DownwardsLines: u32,
    UpwardsLines: u32,
};

pub const Verb = union(enum) {
    Delete: Motion,
};

const ParseState = union(enum) {
    WaitingForVerb,
    WaitingForMotion: Verb,
};

pub fn parseInput(allocator: *mem.Allocator, input: []const u8) !ArrayList(Verb) {
    var verbs = ArrayList(Verb).init(allocator);
    var state: ParseState = ParseState.WaitingForVerb;
    for (input) |c| {
        switch (state) {
            ParseState.WaitingForVerb => {
                switch (c) {
                    'd' => {
                        state = ParseState{
                            .WaitingForMotion = Verb{ .Delete = Motion.Unset },
                        };
                    },
                    else => {},
                }
            },
            ParseState.WaitingForMotion => |*verb| {
                switch (verb.*) {
                    .Delete => |*motion| {
                        switch (c) {
                            'd' => {
                                state = ParseState.WaitingForVerb;
                                motion.* = Motion.NoMotion;
                            },
                            'e' => {
                                state = ParseState.WaitingForVerb;
                                motion.* = Motion.UntilEndOfWord;
                            },
                            'w' => {
                                state = ParseState.WaitingForVerb;
                                motion.* = Motion.UntilNextWord;
                            },
                            'j' => {
                                state = ParseState.WaitingForVerb;
                                motion.* = Motion{ .DownwardsLines = 1 };
                            },
                            'k' => {
                                state = ParseState.WaitingForVerb;
                                motion.* = Motion{ .UpwardsLines = 1 };
                            },
                            else => @panic("unimplemented motion"),
                        }
                        try verbs.append(verb.*);
                    },
                }
            },
        }
    }

    return verbs;
}

test "can get active tag of verb" {
    const verb = Verb{ .Delete = Motion.NoMotion };
    testing.expect(std.meta.activeTag(verb) == Verb.Delete);
    switch (verb) {
        .Delete => |motion| {
            testing.expect(std.meta.activeTag(motion) == Motion.NoMotion);
        },
    }
}

test "`dd` creates a delete verb" {
    const input = "dd"[0..];
    const verbs = try parseInput(direct_allocator, input);
    testing.expectEqual(verbs.count(), 1);
    const verb_slice = verbs.toSliceConst();
    const verb = verb_slice[0];
    testing.expect(std.meta.activeTag(verb) == Verb.Delete);
    switch (verb) {
        .Delete => |motion| {
            testing.expect(std.meta.activeTag(motion) == Motion.NoMotion);
        },
    }
}

test "`dddd` creates two delete verbs" {
    const input = "dddd"[0..];
    const verbs = try parseInput(direct_allocator, input);
    testing.expectEqual(verbs.count(), 2);
    const verb_slice = verbs.toSliceConst();
    for (verb_slice) |verb| {
        testing.expect(std.meta.activeTag(verb) == Verb.Delete);
        switch (verb) {
            .Delete => |motion| {
                testing.expect(std.meta.activeTag(motion) == Motion.NoMotion);
            },
        }
    }
}

test "`ddde` creates two delete verbs, last one until end of word" {
    const input = "ddde"[0..];
    const verbs = try parseInput(direct_allocator, input);
    testing.expectEqual(verbs.count(), 2);
    const verb_slice = verbs.toSliceConst();
    const first_verb = verb_slice[0];
    const second_verb = verb_slice[1];
    testing.expect(std.meta.activeTag(first_verb) == Verb.Delete);
    switch (first_verb) {
        .Delete => |motion| {
            testing.expect(std.meta.activeTag(motion) == Motion.NoMotion);
        },
    }
    testing.expect(std.meta.activeTag(second_verb) == Verb.Delete);
    switch (second_verb) {
        .Delete => |motion| {
            testing.expect(std.meta.activeTag(motion) == Motion.UntilEndOfWord);
        },
    }
}

test "`dw` creates 'delete until next word'" {
    const input = "dw"[0..];
    const verbs = try parseInput(direct_allocator, input);
    testing.expectEqual(verbs.count(), 1);
    const verb_slice = verbs.toSliceConst();
    const first_verb = verb_slice[0];
    testing.expect(std.meta.activeTag(first_verb) == Verb.Delete);
    switch (first_verb) {
        .Delete => |motion| {
            testing.expect(std.meta.activeTag(motion) == Motion.UntilNextWord);
        },
    }
}

test "`dj` creates 'delete one line downwards'" {
    const input = "dj"[0..];
    const verbs = try parseInput(direct_allocator, input);
    testing.expectEqual(verbs.count(), 1);
    const verb_slice = verbs.toSliceConst();
    const first_verb = verb_slice[0];
    testing.expect(std.meta.activeTag(first_verb) == Verb.Delete);
    switch (first_verb) {
        .Delete => |motion| {
            testing.expect(std.meta.activeTag(motion) == Motion.DownwardsLines);
            switch (motion) {
                .DownwardsLines => |lines| {
                    testing.expectEqual(lines, 1);
                },
                else => unreachable,
            }
        },
    }
}

test "`dk` creates 'delete one line upwards'" {
    const input = "dk"[0..];
    const verbs = try parseInput(direct_allocator, input);
    testing.expectEqual(verbs.count(), 1);
    const verb_slice = verbs.toSliceConst();
    const first_verb = verb_slice[0];
    testing.expect(std.meta.activeTag(first_verb) == Verb.Delete);
    switch (first_verb) {
        .Delete => |motion| {
            testing.expect(std.meta.activeTag(motion) == Motion.UpwardsLines);
            switch (motion) {
                .UpwardsLines => |lines| {
                    testing.expectEqual(lines, 1);
                },
                else => unreachable,
            }
        },
    }
}
