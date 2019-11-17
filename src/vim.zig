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
    ForwardsIncluding: ?u8,
    BackwardsIncluding: ?u8,
    ForwardsExcluding: ?u8,
    BackwardsExcluding: ?u8,
};

pub const Verb = union(enum) {
    Delete: Motion,
    Yank: Motion,
};

const VerbBuilderData = struct {
    range: ?u32,
    verb: Verb,
};

const ParseState = union(enum) {
    WaitingForVerbOrRangeModifier,
    WaitingForMotion: VerbBuilderData,
    WaitingForTarget: VerbBuilderData,
};

pub fn parseInput(allocator: *mem.Allocator, input: []const u8) !ArrayList(Verb) {
    var verbs = ArrayList(Verb).init(allocator);
    var state: ParseState = ParseState.WaitingForVerbOrRangeModifier;
    var range_modifier: ?u32 = null;
    var number_of_range_modifiers: u32 = 0;
    for (input) |c| {
        switch (state) {
            ParseState.WaitingForTarget => |*data| {
                switch (data.verb) {
                    .Delete, .Yank => |*motion| {
                        switch (motion.*) {
                            .ForwardsIncluding,
                            .BackwardsIncluding,
                            .ForwardsExcluding,
                            .BackwardsExcluding,
                            => |*target| target.* = c,
                            .Unset,
                            .UntilEndOfWord,
                            .UntilNextWord,
                            .DownwardsLines,
                            .UpwardsLines,
                            => std.debug.panic(
                                "non-target motion waiting for target: {}\n",
                                motion.*,
                            ),
                        }
                    },
                }
                try verbs.append(data.verb);
                state = ParseState.WaitingForVerbOrRangeModifier;
            },
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
                            .WaitingForMotion = VerbBuilderData{
                                .verb = Verb{ .Delete = Motion.Unset },
                                .range = range_modifier,
                            },
                        };
                    },
                    'y' => {
                        state = ParseState{
                            .WaitingForMotion = VerbBuilderData{
                                .verb = Verb{ .Yank = Motion.Unset },
                                .range = range_modifier,
                            },
                        };
                    },
                    else => std.debug.panic(
                        "Not expecting character '{}', waiting for verb or range modifier",
                        c,
                    ),
                }
            },
            ParseState.WaitingForMotion => |*waiting_for_motion_data| {
                switch (waiting_for_motion_data.verb) {
                    .Delete, .Yank => |*motion| {
                        switch (c) {
                            'd', 'y' => {
                                const range = if (waiting_for_motion_data.range) |r| has: {
                                    break :has r - 1;
                                } else 0;
                                motion.* = Motion{ .DownwardsLines = range };
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
                            'f' => {
                                motion.* = Motion{ .ForwardsIncluding = null };
                                state = ParseState{
                                    .WaitingForTarget = VerbBuilderData{
                                        .range = waiting_for_motion_data.range,
                                        .verb = waiting_for_motion_data.verb,
                                    },
                                };
                            },
                            'F' => {
                                motion.* = Motion{ .BackwardsIncluding = null };
                                state = ParseState{
                                    .WaitingForTarget = VerbBuilderData{
                                        .range = waiting_for_motion_data.range,
                                        .verb = waiting_for_motion_data.verb,
                                    },
                                };
                            },
                            't' => {
                                motion.* = Motion{ .ForwardsExcluding = null };
                                state = ParseState{
                                    .WaitingForTarget = VerbBuilderData{
                                        .range = waiting_for_motion_data.range,
                                        .verb = waiting_for_motion_data.verb,
                                    },
                                };
                            },
                            'T' => {
                                motion.* = Motion{ .BackwardsExcluding = null };
                                state = ParseState{
                                    .WaitingForTarget = VerbBuilderData{
                                        .range = waiting_for_motion_data.range,
                                        .verb = waiting_for_motion_data.verb,
                                    },
                                };
                            },
                            else => std.debug.panic("unimplemented motion: {}\n", c),
                        }
                        switch (state) {
                            .WaitingForTarget => {},
                            else => {
                                try verbs.append(waiting_for_motion_data.verb);
                                state = ParseState.WaitingForVerbOrRangeModifier;
                                range_modifier = null;
                                number_of_range_modifiers = 0;
                            },
                        }
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
        else => unreachable,
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
        else => unreachable,
    }
}

test "`dddd` = two delete verbs" {
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
            else => unreachable,
        }
    }
}

test "`ddde` = two delete verbs, last one until end of word" {
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
        else => unreachable,
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
        else => unreachable,
    }
}

test "`dw` = 'delete until next word'" {
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
        else => unreachable,
    }
}

test "`dj` = 'delete one line downwards'" {
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
        else => unreachable,
    }
}

test "`dk` = 'delete one line upwards'" {
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
        else => unreachable,
    }
}

test "`5dj` = 'delete 5 lines downwards'" {
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
        else => unreachable,
    }
}

test "`5dk` = 'delete 5 lines upwards'" {
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
        else => unreachable,
    }
}

test "`5dd` = 'delete 4 lines downwards'" {
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
        else => unreachable,
    }
}

test "`52dd` = 'delete 51 lines downwards'" {
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
        else => unreachable,
    }
}

test "`52dj` = 'delete 52 lines downwards'" {
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
        else => unreachable,
    }
}

test "`5232dj` = 'delete 5232 lines downwards'" {
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
        else => unreachable,
    }
}

test "`5232dj2301dk` = 'delete 5232 lines downwards' & 'delete 2301 lines upwards'" {
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
        else => unreachable,
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
        else => unreachable,
    }
}

test "`5232yy` = 'yank 5231 lines downwards'" {
    const input = "5232yy"[0..];
    const verbs = try parseInput(direct_allocator, input);
    testing.expectEqual(verbs.count(), 1);
    const verb_slice = verbs.toSliceConst();
    const first_verb = verb_slice[0];
    testing.expect(std.meta.activeTag(first_verb) == Verb.Yank);
    switch (first_verb) {
        .Yank => |motion| {
            testing.expect(std.meta.activeTag(motion) == Motion.DownwardsLines);
            switch (motion) {
                .DownwardsLines => |lines| {
                    testing.expectEqual(lines, 5231);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`522yj201yk` = 'yank 522 lines downwards' & 'yank 231 lines upwards'" {
    const input = "522yj201yk"[0..];
    const verbs = try parseInput(direct_allocator, input);
    testing.expectEqual(verbs.count(), 2);
    const verb_slice = verbs.toSliceConst();
    const first_verb = verb_slice[0];
    const second_verb = verb_slice[1];
    testing.expect(std.meta.activeTag(first_verb) == Verb.Yank);
    testing.expect(std.meta.activeTag(second_verb) == Verb.Yank);
    switch (first_verb) {
        .Yank => |motion| {
            testing.expect(std.meta.activeTag(motion) == Motion.DownwardsLines);
            switch (motion) {
                .DownwardsLines => |lines| {
                    testing.expectEqual(lines, 522);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
    switch (second_verb) {
        .Yank => |motion| {
            testing.expect(std.meta.activeTag(motion) == Motion.UpwardsLines);
            switch (motion) {
                .UpwardsLines => |lines| {
                    testing.expectEqual(lines, 201);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`df)` = 'delete to and including )'" {
    const input = "df)"[0..];
    const verbs = try parseInput(direct_allocator, input);
    testing.expectEqual(verbs.count(), 1);
    const verb_slice = verbs.toSliceConst();
    const first_verb = verb_slice[0];
    testing.expect(std.meta.activeTag(first_verb) == Verb.Delete);
    switch (first_verb) {
        .Delete => |motion| {
            testing.expect(std.meta.activeTag(motion) == Motion.ForwardsIncluding);
            switch (motion) {
                .ForwardsIncluding => |character| {
                    testing.expectEqual(character, ')');
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`dF)` = 'delete back to and including )'" {
    const input = "dF)"[0..];
    const verbs = try parseInput(direct_allocator, input);
    testing.expectEqual(verbs.count(), 1);
    const verb_slice = verbs.toSliceConst();
    const first_verb = verb_slice[0];
    testing.expect(std.meta.activeTag(first_verb) == Verb.Delete);
    switch (first_verb) {
        .Delete => |motion| {
            testing.expect(std.meta.activeTag(motion) == Motion.BackwardsIncluding);
            switch (motion) {
                .BackwardsIncluding => |character| {
                    testing.expectEqual(character, ')');
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`dt)` = 'delete to but excluding )'" {
    const input = "dt)"[0..];
    const verbs = try parseInput(direct_allocator, input);
    testing.expectEqual(verbs.count(), 1);
    const verb_slice = verbs.toSliceConst();
    const first_verb = verb_slice[0];
    testing.expect(std.meta.activeTag(first_verb) == Verb.Delete);
    switch (first_verb) {
        .Delete => |motion| {
            testing.expect(std.meta.activeTag(motion) == Motion.ForwardsExcluding);
            switch (motion) {
                .ForwardsExcluding => |character| {
                    testing.expectEqual(character, ')');
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`dT)` = 'delete back to but excluding )'" {
    const input = "dT)"[0..];
    const verbs = try parseInput(direct_allocator, input);
    testing.expectEqual(verbs.count(), 1);
    const verb_slice = verbs.toSliceConst();
    const first_verb = verb_slice[0];
    testing.expect(std.meta.activeTag(first_verb) == Verb.Delete);
    switch (first_verb) {
        .Delete => |motion| {
            testing.expect(std.meta.activeTag(motion) == Motion.BackwardsExcluding);
            switch (motion) {
                .BackwardsExcluding => |character| {
                    testing.expectEqual(character, ')');
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

pub fn runTests() void {}
