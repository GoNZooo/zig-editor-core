const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const direct_allocator = std.heap.direct_allocator;
const ArrayList = std.ArrayList;

pub const VerbData = struct {
    motion: Motion,
    register: ?u8,
};

pub const PasteData = struct {
    register: ?u8,
    range: ?u32,
};

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
    Unset,
    Delete: VerbData,
    Yank: VerbData,
    PasteForwards: PasteData,
    PasteBackwards: PasteData,
};

const VerbBuilderData = struct {
    range: ?u32 = null,
    range_modifiers: u32 = 0,
    register: ?u8 = null,
    verb: Verb = Verb.Unset,
};

const ParseState = union(enum) {
    Start: VerbBuilderData,
    WaitingForMotion: VerbBuilderData,
    WaitingForTarget: VerbBuilderData,
    WaitingForRegisterCharacter: VerbBuilderData,
};

pub fn parseInput(allocator: *mem.Allocator, input: []const u8) !ArrayList(Verb) {
    var verbs = ArrayList(Verb).init(allocator);
    var state: ParseState = ParseState{
        .Start = VerbBuilderData{
            .range = null,
            .register = null,
            .verb = .Unset,
            .range_modifiers = 0,
        },
    };

    for (input) |c| {
        switch (state) {
            ParseState.Start => |*builder_data| {
                switch (c) {
                    '"' => {
                        state = ParseState{ .WaitingForRegisterCharacter = builder_data.* };
                    },
                    '0'...'9' => {
                        const numeric_value = c - '0';
                        if (builder_data.range) |*range| {
                            range.* *= 10;
                            range.* += numeric_value;
                        } else {
                            builder_data.range = numeric_value;
                        }
                        builder_data.range_modifiers += 1;
                    },
                    'd', 'y' => {
                        const verb = verbFromKey(c, builder_data.register, builder_data.range);
                        state = ParseState{
                            .WaitingForMotion = VerbBuilderData{
                                .verb = verb,
                                .register = builder_data.register,
                                .range = builder_data.range,
                            },
                        };
                    },
                    'p', 'P' => {
                        const verb = verbFromKey(c, builder_data.register, builder_data.range);
                        try verbs.append(verb);
                        state = ParseState{ .Start = VerbBuilderData{} };
                    },
                    else => std.debug.panic(
                        "Not expecting character '{}', waiting for verb or range modifier",
                        c,
                    ),
                }
            },

            ParseState.WaitingForRegisterCharacter => |*builder_data| {
                switch (c) {
                    'a'...'z', 'A'...'Z', '+', '*' => {
                        builder_data.register = c;
                        state = ParseState{ .Start = builder_data.* };
                    },
                    else => std.debug.panic("unknown register: {}\n", c),
                }
            },

            ParseState.WaitingForTarget => |*builder_data| {
                switch (builder_data.verb) {
                    .Delete, .Yank => |*verb_data| {
                        switch (verb_data.motion) {
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
                                verb_data.motion,
                            ),
                        }
                    },
                    .PasteForwards, .PasteBackwards => std.debug.panic(
                        "invalid verb for `WaitingForTarget`: {}\n",
                        builder_data.verb,
                    ),
                    .Unset => std.debug.panic("no verb set when waiting for target"),
                }
                try verbs.append(builder_data.verb);
                state = ParseState{ .Start = VerbBuilderData{} };
            },

            ParseState.WaitingForMotion => |*builder_data| {
                switch (builder_data.verb) {
                    .Delete, .Yank => |*verb_data| {
                        switch (c) {
                            'd', 'y', 'e', 'w', 'j', 'k' => {
                                verb_data.motion = motionFromKey(c, builder_data.*);
                            },
                            'f', 'F', 't', 'T' => {
                                verb_data.motion = motionFromKey(c, builder_data.*);
                                state = ParseState{ .WaitingForTarget = builder_data.* };
                            },
                            else => std.debug.panic("unimplemented motion: {}\n", c),
                        }

                        switch (state) {
                            .WaitingForTarget => {},
                            else => {
                                try verbs.append(builder_data.verb);
                                state = ParseState{
                                    .Start = VerbBuilderData{},
                                };
                            },
                        }
                    },
                    .PasteForwards, .PasteBackwards => std.debug.panic(
                        "invalid verb for `WaitingForMotion`: {}\n",
                        builder_data.verb,
                    ),
                    .Unset => std.debug.panic("no verb when waiting for motion"),
                }
            },
        }
    }

    return verbs;
}

fn verbFromKey(character: u8, register: ?u8, range: ?u32) Verb {
    return switch (character) {
        'd' => Verb{ .Delete = VerbData{ .motion = Motion.Unset, .register = register } },
        'y' => Verb{ .Yank = VerbData{ .motion = Motion.Unset, .register = register } },
        'p' => Verb{
            .PasteForwards = PasteData{
                .range = range orelse 1,
                .register = register,
            },
        },
        'P' => Verb{
            .PasteBackwards = PasteData{
                .range = range orelse 1,
                .register = register,
            },
        },
        else => std.debug.panic("unsupported verb key: {}\n", character),
    };
}

fn motionFromKey(character: u8, builder_data: VerbBuilderData) Motion {
    return switch (character) {
        'd', 'y' => Motion{ .DownwardsLines = if (builder_data.range) |r| (r - 1) else 0 },
        'e' => Motion{ .UntilEndOfWord = builder_data.range orelse 1 },
        'w' => Motion{ .UntilNextWord = builder_data.range orelse 1 },
        'j' => Motion{ .DownwardsLines = builder_data.range orelse 1 },
        'k' => Motion{ .UpwardsLines = builder_data.range orelse 1 },
        'f' => Motion{ .ForwardsIncluding = null },
        'F' => Motion{ .BackwardsIncluding = null },
        't' => Motion{ .ForwardsExcluding = null },
        'T' => Motion{ .BackwardsExcluding = null },
        else => std.debug.panic("unsupported motion: {}\n", character),
    };
}

test "can get active tag of verb" {
    const verb = Verb{ .Delete = VerbData{ .motion = Motion.Unset, .register = null } };
    testing.expect(std.meta.activeTag(verb) == Verb.Delete);
    switch (verb) {
        .Delete => |verb_data| {
            testing.expect(std.meta.activeTag(verb_data.motion) == Motion.Unset);
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
        .Delete => |verb_data| {
            testing.expect(std.meta.activeTag(verb_data.motion) == Motion.DownwardsLines);
            switch (verb_data.motion) {
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
            .Delete => |verb_data| {
                testing.expect(std.meta.activeTag(verb_data.motion) == Motion.DownwardsLines);
                switch (verb_data.motion) {
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
        .Delete => |verb_data| {
            testing.expect(std.meta.activeTag(verb_data.motion) == Motion.DownwardsLines);
            switch (verb_data.motion) {
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
        .Delete => |verb_data| {
            testing.expect(std.meta.activeTag(verb_data.motion) == Motion.UntilEndOfWord);
            switch (verb_data.motion) {
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
        .Delete => |verb_data| {
            testing.expect(std.meta.activeTag(verb_data.motion) == Motion.UntilNextWord);
            switch (verb_data.motion) {
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
        .Delete => |verb_data| {
            testing.expect(std.meta.activeTag(verb_data.motion) == Motion.DownwardsLines);
            switch (verb_data.motion) {
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
        .Delete => |verb_data| {
            testing.expect(std.meta.activeTag(verb_data.motion) == Motion.UpwardsLines);
            switch (verb_data.motion) {
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
        .Delete => |verb_data| {
            testing.expect(std.meta.activeTag(verb_data.motion) == Motion.DownwardsLines);
            switch (verb_data.motion) {
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
        .Delete => |verb_data| {
            testing.expect(std.meta.activeTag(verb_data.motion) == Motion.UpwardsLines);
            switch (verb_data.motion) {
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
        .Delete => |verb_data| {
            testing.expect(std.meta.activeTag(verb_data.motion) == Motion.DownwardsLines);
            switch (verb_data.motion) {
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
        .Delete => |verb_data| {
            testing.expect(std.meta.activeTag(verb_data.motion) == Motion.DownwardsLines);
            switch (verb_data.motion) {
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
        .Delete => |verb_data| {
            testing.expect(std.meta.activeTag(verb_data.motion) == Motion.DownwardsLines);
            switch (verb_data.motion) {
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
        .Delete => |verb_data| {
            testing.expect(std.meta.activeTag(verb_data.motion) == Motion.DownwardsLines);
            switch (verb_data.motion) {
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
        .Delete => |verb_data| {
            testing.expect(std.meta.activeTag(verb_data.motion) == Motion.DownwardsLines);
            switch (verb_data.motion) {
                .DownwardsLines => |lines| {
                    testing.expectEqual(lines, 5232);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
    switch (second_verb) {
        .Delete => |verb_data| {
            testing.expect(std.meta.activeTag(verb_data.motion) == Motion.UpwardsLines);
            switch (verb_data.motion) {
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
        .Yank => |verb_data| {
            testing.expect(std.meta.activeTag(verb_data.motion) == Motion.DownwardsLines);
            switch (verb_data.motion) {
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
        .Yank => |verb_data| {
            testing.expect(std.meta.activeTag(verb_data.motion) == Motion.DownwardsLines);
            switch (verb_data.motion) {
                .DownwardsLines => |lines| {
                    testing.expectEqual(lines, 522);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
    switch (second_verb) {
        .Yank => |verb_data| {
            testing.expect(std.meta.activeTag(verb_data.motion) == Motion.UpwardsLines);
            switch (verb_data.motion) {
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
        .Delete => |verb_data| {
            testing.expect(std.meta.activeTag(verb_data.motion) == Motion.ForwardsIncluding);
            switch (verb_data.motion) {
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
        .Delete => |verb_data| {
            testing.expect(std.meta.activeTag(verb_data.motion) == Motion.BackwardsIncluding);
            switch (verb_data.motion) {
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
        .Delete => |verb_data| {
            testing.expect(std.meta.activeTag(verb_data.motion) == Motion.ForwardsExcluding);
            switch (verb_data.motion) {
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
        .Delete => |verb_data| {
            testing.expect(std.meta.activeTag(verb_data.motion) == Motion.BackwardsExcluding);
            switch (verb_data.motion) {
                .BackwardsExcluding => |character| {
                    testing.expectEqual(character, ')');
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`\"add` = 'delete current line into register a'" {
    const input = "\"add"[0..];
    const verbs = try parseInput(direct_allocator, input);
    testing.expectEqual(verbs.count(), 1);
    const verb_slice = verbs.toSliceConst();
    const first_verb = verb_slice[0];
    testing.expect(std.meta.activeTag(first_verb) == Verb.Delete);
    switch (first_verb) {
        .Delete => |verb_data| {
            testing.expect(std.meta.activeTag(verb_data.motion) == Motion.DownwardsLines);
            testing.expectEqual(verb_data.register, 'a');
            switch (verb_data.motion) {
                .DownwardsLines => |lines| {
                    testing.expectEqual(lines, 0);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`\"+5dj` = 'delete 5 lines down into register +'" {
    const input = "\"+5dj"[0..];
    const verbs = try parseInput(direct_allocator, input);
    testing.expectEqual(verbs.count(), 1);
    const verb_slice = verbs.toSliceConst();
    const first_verb = verb_slice[0];
    testing.expect(std.meta.activeTag(first_verb) == Verb.Delete);
    switch (first_verb) {
        .Delete => |verb_data| {
            testing.expect(std.meta.activeTag(verb_data.motion) == Motion.DownwardsLines);
            testing.expectEqual(verb_data.register, '+');
            switch (verb_data.motion) {
                .DownwardsLines => |lines| {
                    testing.expectEqual(lines, 5);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`p` = 'paste forwards'" {
    const input = "p"[0..];
    const verbs = try parseInput(direct_allocator, input);
    testing.expectEqual(verbs.count(), 1);
    const verb_slice = verbs.toSliceConst();
    const first_verb = verb_slice[0];
    testing.expect(std.meta.activeTag(first_verb) == Verb.PasteForwards);
    switch (first_verb) {
        .PasteForwards => |paste_data| {
            testing.expectEqual(paste_data.range, 1);
            testing.expectEqual(paste_data.register, null);
        },
        else => unreachable,
    }
}

test "`\"a3P` = 'paste backwards 3 times from register a'" {
    const input = "\"a3P"[0..];
    const verbs = try parseInput(direct_allocator, input);
    testing.expectEqual(verbs.count(), 1);
    const verb_slice = verbs.toSliceConst();
    const first_verb = verb_slice[0];
    testing.expect(std.meta.activeTag(first_verb) == Verb.PasteBackwards);
    switch (first_verb) {
        .PasteBackwards => |paste_data| {
            testing.expectEqual(paste_data.range, 3);
            testing.expectEqual(paste_data.register, 'a');
        },
        else => unreachable,
    }
}

pub fn runTests() void {}
