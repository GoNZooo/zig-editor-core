const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const direct_allocator = std.heap.direct_allocator;
const ArrayList = std.ArrayList;

pub const CommandData = struct {
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
    UntilEndOfLine: u32,
    UntilBeginningOfLine: u32,
    UntilColumnZero,
    DownwardsLines: u32,
    UpwardsLines: u32,
    ForwardsParagraph: u32,
    BackwardsParagraph: u32,
    ForwardsIncluding: ?u8,
    BackwardsIncluding: ?u8,
    ForwardsExcluding: ?u8,
    BackwardsExcluding: ?u8,
};

pub const Command = union(enum) {
    Unset,
    MotionOnly: CommandData,
    Delete: CommandData,
    Yank: CommandData,
    Change: CommandData,
    PasteForwards: PasteData,
    PasteBackwards: PasteData,
    SetMark: ?u8,
    JumpMarkLine: ?u8,
    JumpMarkPosition: ?u8,
};

const CommandBuilderData = struct {
    range: ?u32 = null,
    range_modifiers: u32 = 0,
    register: ?u8 = null,
    command: Command = Command.Unset,
};

const ParseState = union(enum) {
    Start: CommandBuilderData,
    WaitingForMotion: CommandBuilderData,
    WaitingForTarget: CommandBuilderData,
    WaitingForRegisterCharacter: CommandBuilderData,
    WaitingForMark: CommandBuilderData,
};

pub fn parseInput(allocator: *mem.Allocator, input: []const u8) !ArrayList(Command) {
    var commands = ArrayList(Command).init(allocator);
    var state: ParseState = ParseState{
        .Start = CommandBuilderData{
            .range = null,
            .register = null,
            .command = .Unset,
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
                    'd', 'y', 'c' => {
                        const command = commandFromKey(
                            c,
                            builder_data.register,
                            builder_data.range,
                        );
                        state = ParseState{
                            .WaitingForMotion = CommandBuilderData{
                                .command = command,
                                .register = builder_data.register,
                                .range = builder_data.range,
                            },
                        };
                    },
                    'm', '\'', '`' => {
                        const command = commandFromKey(
                            c,
                            builder_data.register,
                            builder_data.range,
                        );
                        state = ParseState{
                            .WaitingForMark = CommandBuilderData{
                                .command = command,
                                .register = builder_data.register,
                                .range = builder_data.range,
                            },
                        };
                    },
                    'p', 'P', 'j', 'k', '$', '^', '{', '}' => {
                        const command = commandFromKey(
                            c,
                            builder_data.register,
                            builder_data.range,
                        );
                        try commands.append(command);
                        state = ParseState{ .Start = CommandBuilderData{} };
                    },
                    'f', 'F', 't', 'T' => {
                        builder_data.command = commandFromKey(
                            c,
                            builder_data.register,
                            builder_data.range,
                        );

                        state = ParseState{ .WaitingForTarget = builder_data.* };
                    },

                    // @TODO: add 'C' support
                    // Needs to support range + registers

                    // @TODO: add 'D' support
                    // Needs to support range + registers
                    // Interestingly VSCodeVim does not support ranges for `D`

                    else => std.debug.panic(
                        "Not expecting character '{}', waiting for command or range modifier",
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

            ParseState.WaitingForMark => |*builder_data| {
                switch (builder_data.command) {
                    .SetMark, .JumpMarkLine, .JumpMarkPosition => |*mark| {
                        mark.* = c;
                        try commands.append(builder_data.command);
                        state = ParseState{ .Start = CommandBuilderData{} };
                    },
                    .Yank,
                    .PasteForwards,
                    .PasteBackwards,
                    .Delete,
                    .MotionOnly,
                    .Unset,
                    .Change,
                    => std.debug.panic(
                        "Invalid command for `WaitingForMark`: {}\n",
                        builder_data.command,
                    ),
                }
            },

            ParseState.WaitingForTarget => |*builder_data| {
                switch (builder_data.command) {
                    .Delete,
                    .Yank,
                    .Change,
                    .MotionOnly,
                    => |*command_data| {
                        switch (command_data.motion) {
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
                            .ForwardsParagraph,
                            .BackwardsParagraph,
                            .UntilEndOfLine,
                            .UntilBeginningOfLine,
                            .UntilColumnZero,
                            => std.debug.panic(
                                "non-target motion waiting for target: {}\n",
                                command_data.motion,
                            ),
                        }
                    },
                    .PasteForwards,
                    .PasteBackwards,
                    .SetMark,
                    .JumpMarkLine,
                    .JumpMarkPosition,
                    => std.debug.panic(
                        "invalid command for `WaitingForTarget`: {}\n",
                        builder_data.command,
                    ),
                    .Unset => std.debug.panic("no command set when waiting for target"),
                }
                try commands.append(builder_data.command);
                state = ParseState{ .Start = CommandBuilderData{} };
            },

            ParseState.WaitingForMotion => |*builder_data| {
                switch (builder_data.command) {
                    .Delete, .Yank, .Change => |*command_data| {
                        switch (c) {
                            'd', 'y', 'e', 'w', 'j', 'k', '$', '^', 'c', '{', '}', '0' => {
                                command_data.motion = motionFromKey(c, builder_data.*);
                            },
                            'f', 'F', 't', 'T' => {
                                command_data.motion = motionFromKey(c, builder_data.*);
                                state = ParseState{ .WaitingForTarget = builder_data.* };
                            },
                            else => std.debug.panic("unimplemented motion: {}\n", c),
                        }

                        switch (state) {
                            .WaitingForTarget => {},
                            else => {
                                try commands.append(builder_data.command);
                                state = ParseState{
                                    .Start = CommandBuilderData{},
                                };
                            },
                        }
                    },
                    .PasteForwards,
                    .PasteBackwards,
                    .MotionOnly,
                    .SetMark,
                    .JumpMarkLine,
                    .JumpMarkPosition,
                    => std.debug.panic(
                        "invalid command for `WaitingForMotion`: {}\n",
                        builder_data.command,
                    ),
                    .Unset => std.debug.panic("no command when waiting for motion"),
                }
            },
        }
    }

    return commands;
}

fn commandFromKey(character: u8, register: ?u8, range: ?u32) Command {
    return switch (character) {
        'd' => Command{ .Delete = CommandData{ .motion = Motion.Unset, .register = register } },
        'y' => Command{ .Yank = CommandData{ .motion = Motion.Unset, .register = register } },
        'c' => Command{ .Change = CommandData{ .motion = Motion.Unset, .register = register } },
        'p' => Command{
            .PasteForwards = PasteData{
                .range = range orelse 1,
                .register = register,
            },
        },
        'P' => Command{
            .PasteBackwards = PasteData{
                .range = range orelse 1,
                .register = register,
            },
        },
        'j' => Command{
            .MotionOnly = CommandData{
                .motion = Motion{ .DownwardsLines = range orelse 1 },
                .register = register,
            },
        },
        'k' => Command{
            .MotionOnly = CommandData{
                .motion = Motion{ .UpwardsLines = range orelse 1 },
                .register = register,
            },
        },
        '$' => Command{
            .MotionOnly = CommandData{
                .motion = Motion{ .UntilEndOfLine = range orelse 1 },
                .register = register,
            },
        },
        '^' => Command{
            .MotionOnly = CommandData{
                .motion = Motion{ .UntilBeginningOfLine = range orelse 1 },
                .register = register,
            },
        },
        '}' => Command{
            .MotionOnly = CommandData{
                .motion = Motion{ .ForwardsParagraph = range orelse 1 },
                .register = register,
            },
        },
        '{' => Command{
            .MotionOnly = CommandData{
                .motion = Motion{ .BackwardsParagraph = range orelse 1 },
                .register = register,
            },
        },
        'f' => Command{
            .MotionOnly = CommandData{
                .motion = Motion{ .ForwardsIncluding = null },
                .register = register,
            },
        },
        'F' => Command{
            .MotionOnly = CommandData{
                .motion = Motion{ .BackwardsIncluding = null },
                .register = register,
            },
        },
        't' => Command{
            .MotionOnly = CommandData{
                .motion = Motion{ .ForwardsExcluding = null },
                .register = register,
            },
        },
        'T' => Command{
            .MotionOnly = CommandData{
                .motion = Motion{ .BackwardsExcluding = null },
                .register = register,
            },
        },
        'm' => Command{ .SetMark = null },
        '\'' => Command{ .JumpMarkLine = null },
        '`' => Command{ .JumpMarkPosition = null },
        else => std.debug.panic("unsupported command key: {}\n", character),
    };
}

fn motionFromKey(character: u8, builder_data: CommandBuilderData) Motion {
    return switch (character) {
        'd', 'y', 'c' => Motion{ .DownwardsLines = if (builder_data.range) |r| (r - 1) else 0 },
        'e' => Motion{ .UntilEndOfWord = builder_data.range orelse 1 },
        'w' => Motion{ .UntilNextWord = builder_data.range orelse 1 },
        'j' => Motion{ .DownwardsLines = builder_data.range orelse 1 },
        'k' => Motion{ .UpwardsLines = builder_data.range orelse 1 },
        '$' => Motion{ .UntilEndOfLine = if (builder_data.range) |r| (r - 1) else 1 },
        '^' => Motion{ .UntilBeginningOfLine = if (builder_data.range) |r| (r - 1) else 1 },
        'f' => Motion{ .ForwardsIncluding = null },
        'F' => Motion{ .BackwardsIncluding = null },
        't' => Motion{ .ForwardsExcluding = null },
        'T' => Motion{ .BackwardsExcluding = null },
        '}' => Motion{ .ForwardsParagraph = builder_data.range orelse 1 },
        '{' => Motion{ .BackwardsParagraph = builder_data.range orelse 1 },
        '0' => Motion.UntilColumnZero,
        else => std.debug.panic("unsupported motion: {}\n", character),
    };
}

test "can get active tag of command" {
    const command = Command{ .Delete = CommandData{ .motion = Motion.Unset, .register = null } };
    testing.expect(std.meta.activeTag(command) == Command.Delete);
    switch (command) {
        .Delete => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.Unset);
        },
        else => unreachable,
    }
}

test "`dd` creates a delete command" {
    const input = "dd"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const command = command_slice[0];
    testing.expect(std.meta.activeTag(command) == Command.Delete);
    switch (command) {
        .Delete => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.DownwardsLines);
            switch (command_data.motion) {
                .DownwardsLines => |lines| {
                    testing.expectEqual(lines, 0);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`dddd` = two delete commands" {
    const input = "dddd"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 2);
    const command_slice = commands.toSliceConst();
    for (command_slice) |command| {
        testing.expect(std.meta.activeTag(command) == Command.Delete);
        switch (command) {
            .Delete => |command_data| {
                testing.expect(std.meta.activeTag(command_data.motion) == Motion.DownwardsLines);
                switch (command_data.motion) {
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

test "`ddde` = two delete commands, last one until end of word" {
    const input = "ddde"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 2);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    const second_command = command_slice[1];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.DownwardsLines);
            switch (command_data.motion) {
                .DownwardsLines => |lines| {
                    testing.expectEqual(lines, 0);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
    testing.expect(std.meta.activeTag(second_command) == Command.Delete);
    switch (second_command) {
        .Delete => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UntilEndOfWord);
            switch (command_data.motion) {
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
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UntilNextWord);
            switch (command_data.motion) {
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
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.DownwardsLines);
            switch (command_data.motion) {
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
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UpwardsLines);
            switch (command_data.motion) {
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
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.DownwardsLines);
            switch (command_data.motion) {
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
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UpwardsLines);
            switch (command_data.motion) {
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
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.DownwardsLines);
            switch (command_data.motion) {
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
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.DownwardsLines);
            switch (command_data.motion) {
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
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.DownwardsLines);
            switch (command_data.motion) {
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
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.DownwardsLines);
            switch (command_data.motion) {
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
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 2);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    const second_command = command_slice[1];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    testing.expect(std.meta.activeTag(second_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.DownwardsLines);
            switch (command_data.motion) {
                .DownwardsLines => |lines| {
                    testing.expectEqual(lines, 5232);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
    switch (second_command) {
        .Delete => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UpwardsLines);
            switch (command_data.motion) {
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
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Yank);
    switch (first_command) {
        .Yank => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.DownwardsLines);
            switch (command_data.motion) {
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
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 2);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    const second_command = command_slice[1];
    testing.expect(std.meta.activeTag(first_command) == Command.Yank);
    testing.expect(std.meta.activeTag(second_command) == Command.Yank);
    switch (first_command) {
        .Yank => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.DownwardsLines);
            switch (command_data.motion) {
                .DownwardsLines => |lines| {
                    testing.expectEqual(lines, 522);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
    switch (second_command) {
        .Yank => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UpwardsLines);
            switch (command_data.motion) {
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
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.ForwardsIncluding);
            switch (command_data.motion) {
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
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.BackwardsIncluding);
            switch (command_data.motion) {
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
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.ForwardsExcluding);
            switch (command_data.motion) {
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
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.BackwardsExcluding);
            switch (command_data.motion) {
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
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.DownwardsLines);
            testing.expectEqual(command_data.register, 'a');
            switch (command_data.motion) {
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
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.DownwardsLines);
            testing.expectEqual(command_data.register, '+');
            switch (command_data.motion) {
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
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.PasteForwards);
    switch (first_command) {
        .PasteForwards => |paste_data| {
            testing.expectEqual(paste_data.range, 1);
            testing.expectEqual(paste_data.register, null);
        },
        else => unreachable,
    }
}

test "`\"a3P` = 'paste backwards 3 times from register a'" {
    const input = "\"a3P"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.PasteBackwards);
    switch (first_command) {
        .PasteBackwards => |paste_data| {
            testing.expectEqual(paste_data.range, 3);
            testing.expectEqual(paste_data.register, 'a');
        },
        else => unreachable,
    }
}

test "`d$` = 'delete until end of line'" {
    const input = "d$"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UntilEndOfLine);
            switch (command_data.motion) {
                .UntilEndOfLine => |optional_lines| {
                    testing.expectEqual(optional_lines, 1);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`d^` = 'delete until beginning of line'" {
    const input = "d^"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UntilBeginningOfLine);
            switch (command_data.motion) {
                .UntilBeginningOfLine => |optional_lines| {
                    testing.expectEqual(optional_lines, 1);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`cc` = 'change current line'" {
    const input = "cc"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Change);
    switch (first_command) {
        .Change => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.DownwardsLines);
            switch (command_data.motion) {
                .DownwardsLines => |lines| {
                    testing.expectEqual(lines, 0);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`cfe` = 'change until e forwards'" {
    const input = "cfe"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Change);
    switch (first_command) {
        .Change => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.ForwardsIncluding);
            switch (command_data.motion) {
                .ForwardsIncluding => |character| {
                    testing.expectEqual(character, 'e');
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`\"*cT$` = 'change backwards until but excluding the character $ into register *'" {
    const input = "\"*cT$"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Change);
    switch (first_command) {
        .Change => |command_data| {
            testing.expectEqual(command_data.register, '*');
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.BackwardsExcluding);
            switch (command_data.motion) {
                .BackwardsExcluding => |character| {
                    testing.expectEqual(character, '$');
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`15c$` = 'change to end of line downwards 14 lines'" {
    const input = "15c$"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Change);
    switch (first_command) {
        .Change => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UntilEndOfLine);
            switch (command_data.motion) {
                .UntilEndOfLine => |lines| {
                    testing.expectEqual(lines, 14);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`15j` = 'move down 15 lines'" {
    const input = "15j"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.MotionOnly);
    switch (first_command) {
        .MotionOnly => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.DownwardsLines);
            switch (command_data.motion) {
                .DownwardsLines => |lines| {
                    testing.expectEqual(lines, 15);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`14$` = 'move to the end of the line, 14 lines down'" {
    const input = "14$"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.MotionOnly);
    switch (first_command) {
        .MotionOnly => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UntilEndOfLine);
            switch (command_data.motion) {
                .UntilEndOfLine => |lines| {
                    testing.expectEqual(lines, 14);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`3f\"` = 'move to the third ocurrence forwards of \"'" {
    const input = "3f\""[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.MotionOnly);
    switch (first_command) {
        .MotionOnly => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.ForwardsIncluding);
            switch (command_data.motion) {
                .ForwardsIncluding => |character| {
                    testing.expectEqual(character, '\"');
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`150F(` = 'move unto the 150th ocurrence backwards of ('" {
    const input = "150F("[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.MotionOnly);
    switch (first_command) {
        .MotionOnly => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.BackwardsIncluding);
            switch (command_data.motion) {
                .BackwardsIncluding => |character| {
                    testing.expectEqual(character, '(');
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`2T(` = 'move to the 2nd ocurrence backwards of ('" {
    const input = "2T("[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.MotionOnly);
    switch (first_command) {
        .MotionOnly => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.BackwardsExcluding);
            switch (command_data.motion) {
                .BackwardsExcluding => |character| {
                    testing.expectEqual(character, '(');
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`15t)` = 'move to the 15th ocurrence forwards of )'" {
    const input = "15t)"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.MotionOnly);
    switch (first_command) {
        .MotionOnly => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.ForwardsExcluding);
            switch (command_data.motion) {
                .ForwardsExcluding => |character| {
                    testing.expectEqual(character, ')');
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`\"u2d}` = 'delete 2 paragraphs forwards into register u'" {
    const input = "\"u2d}"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expectEqual(command_data.register, 'u');
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.ForwardsParagraph);
            switch (command_data.motion) {
                .ForwardsParagraph => |paragraphs| {
                    testing.expectEqual(paragraphs, 2);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`\"o15y{` = 'yank 15 paragraphs backwards into register o'" {
    const input = "\"o15y{"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Yank);
    switch (first_command) {
        .Yank => |command_data| {
            testing.expectEqual(command_data.register, 'o');
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.BackwardsParagraph);
            switch (command_data.motion) {
                .BackwardsParagraph => |paragraphs| {
                    testing.expectEqual(paragraphs, 15);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`}2{` = 'go forward one paragraph, go back two paragraphs'" {
    const input = "}2{"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 2);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    const second_command = command_slice[1];
    testing.expect(std.meta.activeTag(first_command) == Command.MotionOnly);
    switch (first_command) {
        .MotionOnly => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.ForwardsParagraph);
            switch (command_data.motion) {
                .ForwardsParagraph => |paragraphs| {
                    testing.expectEqual(paragraphs, 1);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
    switch (second_command) {
        .MotionOnly => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.BackwardsParagraph);
            switch (command_data.motion) {
                .BackwardsParagraph => |paragraphs| {
                    testing.expectEqual(paragraphs, 2);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`\"ay0\"a3p` = 'yank until column zero into register a, paste from register a 3 times'" {
    const input = "\"ay0\"a3p"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 2);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    const second_command = command_slice[1];
    testing.expect(std.meta.activeTag(first_command) == Command.Yank);
    switch (first_command) {
        .Yank => |command_data| {
            testing.expectEqual(command_data.register, 'a');
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UntilColumnZero);
        },
        else => unreachable,
    }
    switch (second_command) {
        .PasteForwards => |paste_data| {
            testing.expectEqual(paste_data.register, 'a');
            testing.expectEqual(paste_data.range, 3);
        },
        else => unreachable,
    }
}

test "`maj'a` = 'set mark a, move one line down, move to mark a's line'" {
    const input = "maj'a"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 3);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    const second_command = command_slice[1];
    const third_command = command_slice[2];
    testing.expect(std.meta.activeTag(first_command) == Command.SetMark);
    switch (first_command) {
        .SetMark => |mark| {
            testing.expectEqual(mark, 'a');
        },
        else => unreachable,
    }
    switch (second_command) {
        .MotionOnly => |command_data| {
            testing.expectEqual(command_data.register, null);
            switch (command_data.motion) {
                .DownwardsLines => |lines| {
                    testing.expectEqual(lines, 1);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
    switch (third_command) {
        .JumpMarkLine => |mark| testing.expectEqual(mark, 'a'),
        else => unreachable,
    }
}

test "`maj`a` = 'set mark a, move one line down, move to mark a's position'" {
    const input = "maj`a"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 3);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    const second_command = command_slice[1];
    const third_command = command_slice[2];
    testing.expect(std.meta.activeTag(first_command) == Command.SetMark);
    switch (first_command) {
        .SetMark => |mark| {
            testing.expectEqual(mark, 'a');
        },
        else => unreachable,
    }
    switch (second_command) {
        .MotionOnly => |command_data| {
            testing.expectEqual(command_data.register, null);
            switch (command_data.motion) {
                .DownwardsLines => |lines| {
                    testing.expectEqual(lines, 1);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
    switch (third_command) {
        .JumpMarkPosition => |mark| testing.expectEqual(mark, 'a'),
        else => unreachable,
    }
}

pub fn runTests() void {}
