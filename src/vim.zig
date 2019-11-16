const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const direct_allocator = std.heap.direct_allocator;
const ArrayList = std.ArrayList;

pub const Motion = union(enum) {
    Unset,
    UntilEndOfWord: u32,
    UntilNextWord: u32,
    DownwardsLines: u32,
    UpwardsLines: u32,
};

pub const Verb = union(enum) {
    Delete: Motion,
};

const WaitingForMotionData = struct {
    range: ?u32,
    verb: Verb,
};

const ParseState = union(enum) {
    WaitingForVerbOrRangeModifier,
    WaitingForMotion: WaitingForMotionData,
};

pub fn parseInput(allocator: *mem.Allocator, input: []const u8) !ArrayList(Verb) {
    var verbs = ArrayList(Verb).init(allocator);
    var state: ParseState = ParseState.WaitingForVerbOrRangeModifier;
    var range_modifier: ?u32 = null;
    var number_of_range_modifiers: u32 = 0;
    for (input) |c| {
        switch (state) {
            ParseState.WaitingForVerbOrRangeModifier => {
                switch (c) {
                    '0'...'9' => {
                        const numeric_value = c - '0';
                        if (range_modifier) |*modifier| {
                            modifier.* *= 10;
                            modifier.* += numeric_value;
                        } else {
                            range_modifier = numeric_value;
                        }
                        number_of_range_modifiers += 1;
                    },
                    'd' => {
                        state = ParseState{
                            .WaitingForMotion = WaitingForMotionData{
                                .verb = Verb{ .Delete = Motion.Unset },
                                .range = range_modifier,
                            },
                        };
                    },
                    else => {},
                }
            },
            ParseState.WaitingForMotion => |*waiting_for_motion_data| {
                switch (waiting_for_motion_data.verb) {
                    .Delete => |*motion| {
                        switch (c) {
                            'd' => {
                                const range = if (waiting_for_motion_data.range) |r| has: {
                                    break :has r - 1;
                                } else 0;
                                motion.* = Motion{
                                    .DownwardsLines = range,
                                };
                            },
                            'e' => {
                                motion.* = Motion{
                                    .UntilEndOfWord = waiting_for_motion_data.range orelse 1,
                                };
                            },
                            'w' => {
                                motion.* = Motion{
                                    .UntilNextWord = waiting_for_motion_data.range orelse 1,
                                };
                            },
                            'j' => {
                                motion.* = Motion{
                                    .DownwardsLines = waiting_for_motion_data.range orelse 1,
                                };
                            },
                            'k' => {
                                motion.* = Motion{
                                    .UpwardsLines = waiting_for_motion_data.range orelse 1,
                                };
                            },
                            else => @panic("unimplemented motion"),
                        }
                        try verbs.append(waiting_for_motion_data.verb);
                        state = ParseState.WaitingForVerbOrRangeModifier;
                        range_modifier = null;
                        number_of_range_modifiers = 0;
                    },
                }
            },
        }
    }

    return verbs;
}

test "can get active tag of verb" {
    const verb = Verb{ .Delete = Motion.Unset };
    testing.expect(std.meta.activeTag(verb) == Verb.Delete);
    switch (verb) {
        .Delete => |motion| {
            testing.expect(std.meta.activeTag(motion) == Motion.Unset);
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
            testing.expect(std.meta.activeTag(motion) == Motion.DownwardsLines);
            switch (motion) {
                .DownwardsLines => |lines| {
                    testing.expectEqual(lines, 0);
                },
                else => unreachable,
            }
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
                testing.expect(std.meta.activeTag(motion) == Motion.DownwardsLines);
                switch (motion) {
                    .DownwardsLines => |lines| {
                        testing.expectEqual(lines, 0);
                    },
                    else => unreachable,
                }
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
            testing.expect(std.meta.activeTag(motion) == Motion.DownwardsLines);
            switch (motion) {
                .DownwardsLines => |lines| {
                    testing.expectEqual(lines, 0);
                },
                else => unreachable,
            }
        },
    }
    testing.expect(std.meta.activeTag(second_verb) == Verb.Delete);
    switch (second_verb) {
        .Delete => |motion| {
            testing.expect(std.meta.activeTag(motion) == Motion.UntilEndOfWord);
            switch (motion) {
                .UntilEndOfWord => |words| {
                    testing.expectEqual(words, 1);
                },
                else => unreachable,
            }
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
            switch (motion) {
                .UntilNextWord => |words| {
                    testing.expectEqual(words, 1);
                },
                else => unreachable,
            }
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

test "`5dj` creates 'delete 5 lines downwards'" {
    const input = "5dj"[0..];
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
                    testing.expectEqual(lines, 5);
                },
                else => unreachable,
            }
        },
    }
}

test "`5dk` creates 'delete 5 lines upwards'" {
    const input = "5dk"[0..];
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
                    testing.expectEqual(lines, 5);
                },
                else => unreachable,
            }
        },
    }
}

test "`5dd` creates 'delete 4 lines downwards'" {
    const input = "5dd"[0..];
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
                    testing.expectEqual(lines, 4);
                },
                else => unreachable,
            }
        },
    }
}

test "`52dd` creates 'delete 51 lines downwards'" {
    const input = "52dd"[0..];
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
                    testing.expectEqual(lines, 51);
                },
                else => unreachable,
            }
        },
    }
}

test "`52dj` creates 'delete 52 lines downwards'" {
    const input = "52dj"[0..];
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
                    testing.expectEqual(lines, 52);
                },
                else => unreachable,
            }
        },
    }
}

test "`5232dj` creates 'delete 5232 lines downwards'" {
    const input = "5232dj"[0..];
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
                    testing.expectEqual(lines, 5232);
                },
                else => unreachable,
            }
        },
    }
}

test "`5232dj2301dk` creates 'delete 5232 lines downwards' & 'delete 2301 lines upwards'" {
    const input = "5232dj2301dk"[0..];
    const verbs = try parseInput(direct_allocator, input);
    testing.expectEqual(verbs.count(), 2);
    const verb_slice = verbs.toSliceConst();
    const first_verb = verb_slice[0];
    const second_verb = verb_slice[1];
    testing.expect(std.meta.activeTag(first_verb) == Verb.Delete);
    testing.expect(std.meta.activeTag(second_verb) == Verb.Delete);
    switch (first_verb) {
        .Delete => |motion| {
            testing.expect(std.meta.activeTag(motion) == Motion.DownwardsLines);
            switch (motion) {
                .DownwardsLines => |lines| {
                    testing.expectEqual(lines, 5232);
                },
                else => unreachable,
            }
        },
    }
    switch (second_verb) {
        .Delete => |motion| {
            testing.expect(std.meta.activeTag(motion) == Motion.UpwardsLines);
            switch (motion) {
                .UpwardsLines => |lines| {
                    testing.expectEqual(lines, 2301);
                },
                else => unreachable,
            }
        },
    }
}

pub fn runTests() void {}
