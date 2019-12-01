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
    UntilBeginningOfFile: u32,
    UntilEndOfFile: u32,
    DownwardsLines: u32,
    UpwardsLines: u32,
    ForwardsCharacter: u32,
    BackwardsCharacter: u32,
    ForwardsParagraph: u32,
    BackwardsParagraph: u32,
    ForwardsIncluding: ?u8,
    BackwardsIncluding: ?u8,
    ForwardsExcluding: ?u8,
    BackwardsExcluding: ?u8,
    ToMarkLine: ?u8,
    ToMarkPosition: ?u8,
    Inside: ?u8,
    Surrounding: ?u8,
    ToMatching,
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
    Comment: CommandData,
    BringLineUp: u32,
    Undo,
    EnterInsertMode: u32,
    Insert: u8,
    ExitInsertMode,
    ReplaceInsert: ReplaceInsertData,
    // @NOTE: `Insert{Upwards,Downwards} are actually supposed to insert on all lines when using
    // ranges, but the current insert mode doesn't handle this (2019-12-01). It could be solved via
    // on the client interpretation side via spawning multiple cursors as a response to the range
    // attribute, but punting it to the client seems awkward. With that said, this is not a use case
    // that I'm going to necessarily miss if it never gets implemented...
    InsertDownwards: u32,
    InsertUpwards: u32,
    ScrollTop,
    ScrollCenter,
    ScrollBottom,
};

const ReplaceInsertData = struct {
    register: ?u8,
    range: u32,
};

const CommandBuilderData = struct {
    range: ?u32 = null,
    range_modifiers: u32 = 0,
    register: ?u8 = null,
    command: Command = Command.Unset,
};

const InsertModeData = struct {
    range: ?u32 = null,
    range_modifiers: u32 = 0,
};

const InsertData = struct {
    character: u8,
    range: u32,
};

const State = union(enum) {
    Start: CommandBuilderData,
    InInsertMode: InsertModeData,
    WaitingForMotion: CommandBuilderData,
    WaitingForTarget: CommandBuilderData,
    WaitingForRegisterCharacter: CommandBuilderData,
    WaitingForMark: CommandBuilderData,
    WaitingForGCommand: CommandBuilderData,
    WaitingForZCommand: CommandBuilderData,
};

fn parseCharacter(c: u8, state: *State) ?Command {
    switch (state.*) {
        State.Start => |*builder_data| {
            switch (c) {
                '"' => {
                    state.* = State{ .WaitingForRegisterCharacter = builder_data.* };

                    return null;
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

                    return null;
                },
                'd', 'y', 'c' => {
                    builder_data.command = commandFromKey(
                        c,
                        builder_data.register,
                        builder_data.range,
                    );
                    state.* = State{ .WaitingForMotion = builder_data.* };

                    return null;
                },
                'm', '\'', '`' => {
                    builder_data.command = commandFromKey(
                        c,
                        builder_data.register,
                        builder_data.range,
                    );
                    state.* = State{ .WaitingForMark = builder_data.* };

                    return null;
                },
                'p', 'P', 'j', 'k', '$', '^', '{', '}', 'l', 'h', 'G', 'J', 'u' => {
                    const command = commandFromKey(
                        c,
                        builder_data.register,
                        builder_data.range,
                    );
                    state.* = State{ .Start = CommandBuilderData{} };

                    return command;
                },
                'f', 'F', 't', 'T' => {
                    builder_data.command = commandFromKey(
                        c,
                        builder_data.register,
                        builder_data.range,
                    );
                    state.* = State{ .WaitingForTarget = builder_data.* };

                    return null;
                },
                'g' => {
                    state.* = State{ .WaitingForGCommand = builder_data.* };

                    return null;
                },
                'z' => {
                    state.* = State{ .WaitingForZCommand = builder_data.* };

                    return null;
                },
                'i', 's', 'o', 'O' => {
                    const command = commandFromKey(c, builder_data.register, builder_data.range);
                    state.* = State{ .InInsertMode = InsertModeData{} };

                    return command;
                },

                // @TODO: add 'C' support
                // Needs to support range + registers

                // @TODO: add 'D' support
                // Needs to support range + registers
                // Interestingly VSCodeVim does not support ranges for `D` though Vim does

                else => std.debug.panic(
                    "Not expecting character '{c}', waiting for command or range modifier",
                    c,
                ),
            }
        },

        State.WaitingForRegisterCharacter => |*builder_data| {
            switch (c) {
                'a'...'z', 'A'...'Z', '+', '*' => {
                    builder_data.register = c;
                    state.* = State{ .Start = builder_data.* };

                    return null;
                },
                else => std.debug.panic("unknown register: {}\n", c),
            }
        },

        State.WaitingForMark => |*builder_data| {
            switch (builder_data.command) {
                .SetMark => |*mark| {
                    mark.* = c;
                    const command = builder_data.command;
                    state.* = State{ .Start = CommandBuilderData{} };

                    return command;
                },
                .Yank, .Delete, .Change, .MotionOnly, .Comment => |*command_data| {
                    switch (command_data.motion) {
                        .ToMarkLine, .ToMarkPosition => |*mark| {
                            mark.* = c;
                            const command = builder_data.command;
                            state.* = State{ .Start = CommandBuilderData{} };

                            return command;
                        },
                        .BackwardsExcluding,
                        .BackwardsIncluding,
                        .ForwardsIncluding,
                        .ForwardsExcluding,
                        .UntilBeginningOfLine,
                        .UntilColumnZero,
                        .UntilEndOfLine,
                        .UntilEndOfWord,
                        .UntilNextWord,
                        .UpwardsLines,
                        .DownwardsLines,
                        .BackwardsParagraph,
                        .ForwardsParagraph,
                        .BackwardsCharacter,
                        .ForwardsCharacter,
                        .Unset,
                        .Inside,
                        .Surrounding,
                        .UntilEndOfFile,
                        .UntilBeginningOfFile,
                        .ToMatching,
                        => {
                            std.debug.panic(
                                "invalid motion for `WaitingForMark`: {}\n",
                                command_data.motion,
                            );
                        },
                    }
                },
                .PasteForwards,
                .PasteBackwards,
                .Unset,
                .BringLineUp,
                .Undo,
                .EnterInsertMode,
                .Insert,
                .ExitInsertMode,
                .ReplaceInsert,
                .InsertDownwards,
                .InsertUpwards,
                .ScrollTop,
                .ScrollCenter,
                .ScrollBottom,
                => std.debug.panic(
                    "Invalid command for `WaitingForMark`: {}\n",
                    builder_data.command,
                ),
            }
        },

        State.WaitingForTarget => |*builder_data| {
            switch (builder_data.command) {
                .Delete,
                .Yank,
                .Change,
                .MotionOnly,
                .Comment,
                => |*command_data| {
                    switch (command_data.motion) {
                        .ForwardsIncluding,
                        .BackwardsIncluding,
                        .ForwardsExcluding,
                        .BackwardsExcluding,
                        .Inside,
                        .Surrounding,
                        => |*target| {
                            target.* = c;
                            const command = builder_data.command;
                            state.* = State{ .Start = CommandBuilderData{} };

                            return command;
                        },
                        .Unset,
                        .UntilEndOfWord,
                        .UntilNextWord,
                        .DownwardsLines,
                        .UpwardsLines,
                        .ForwardsParagraph,
                        .BackwardsParagraph,
                        .ForwardsCharacter,
                        .BackwardsCharacter,
                        .UntilEndOfLine,
                        .UntilBeginningOfLine,
                        .UntilColumnZero,
                        .ToMarkLine,
                        .ToMarkPosition,
                        .UntilEndOfFile,
                        .UntilBeginningOfFile,
                        .ToMatching,
                        => std.debug.panic(
                            "non-target motion waiting for target: {}\n",
                            command_data.motion,
                        ),
                    }
                },
                .PasteForwards,
                .PasteBackwards,
                .SetMark,
                .BringLineUp,
                .Undo,
                .EnterInsertMode,
                .Insert,
                .ExitInsertMode,
                .ReplaceInsert,
                .InsertDownwards,
                .InsertUpwards,
                .ScrollTop,
                .ScrollCenter,
                .ScrollBottom,
                => std.debug.panic(
                    "invalid command for `WaitingForTarget`: {}\n",
                    builder_data.command,
                ),
                .Unset => std.debug.panic("no command set when waiting for target"),
            }
        },

        State.WaitingForMotion => |*builder_data| {
            switch (builder_data.command) {
                .Delete, .Yank, .Change, .Comment => |*command_data| {
                    switch (c) {
                        '1'...'9' => {
                            const numeric_value = c - '0';
                            if (builder_data.range) |*range| {
                                range.* *= 10;
                                range.* += numeric_value;
                            } else {
                                builder_data.range = numeric_value;
                            }
                            builder_data.range_modifiers += 1;

                            return null;
                        },
                        '0' => {
                            if (builder_data.range) |*range| {
                                range.* *= 10;

                                return null;
                            } else {
                                command_data.motion = motionFromKey(c, builder_data.*);
                                const command = builder_data.command;
                                state.* = State{ .Start = CommandBuilderData{} };

                                return command;
                            }
                        },
                        'd',
                        'y',
                        'e',
                        'w',
                        'j',
                        'k',
                        '$',
                        '^',
                        'c',
                        '{',
                        '}',
                        'l',
                        'h',
                        'G',
                        '%',
                        => {
                            command_data.motion = motionFromKey(c, builder_data.*);
                            const command = builder_data.command;
                            state.* = State{ .Start = CommandBuilderData{} };

                            return command;
                        },
                        'f', 'F', 't', 'T', 'i', 's' => {
                            command_data.motion = motionFromKey(c, builder_data.*);
                            state.* = State{ .WaitingForTarget = builder_data.* };

                            return null;
                        },
                        '`', '\'' => {
                            command_data.motion = motionFromKey(c, builder_data.*);
                            state.* = State{ .WaitingForMark = builder_data.* };

                            return null;
                        },
                        'g' => {
                            state.* = State{ .WaitingForGCommand = builder_data.* };

                            return null;
                        },
                        else => std.debug.panic("unimplemented motion: {c}\n", c),
                    }
                },
                .PasteForwards,
                .PasteBackwards,
                .MotionOnly,
                .SetMark,
                .BringLineUp,
                .Undo,
                .EnterInsertMode,
                .Insert,
                .ExitInsertMode,
                .ReplaceInsert,
                .InsertDownwards,
                .InsertUpwards,
                .ScrollTop,
                .ScrollCenter,
                .ScrollBottom,
                => std.debug.panic(
                    "invalid command for `WaitingForMotion`: {}\n",
                    builder_data.command,
                ),
                .Unset => std.debug.panic("no command when waiting for motion"),
            }
        },

        State.WaitingForGCommand => |*builder_data| {
            return gCommandFromKey(c, state);
        },

        State.WaitingForZCommand => |*builder_data| {
            return zCommandFromKey(c, state);
        },

        State.InInsertMode => |*insert_mode_data| {
            return switch (c) {
                ESCAPE_KEY => i: {
                    const command: Command = Command.ExitInsertMode;
                    state.* = State{ .Start = CommandBuilderData{} };

                    break :i command;
                },
                else => |character| i: {
                    break :i Command{ .Insert = character };
                },
            };
        },
    }
}

pub fn parseInput(allocator: *mem.Allocator, input: []const u8) !ArrayList(Command) {
    var commands = ArrayList(Command).init(allocator);
    errdefer commands.deinit();
    var state: State = State{
        .Start = CommandBuilderData{
            .range = null,
            .register = null,
            .command = .Unset,
            .range_modifiers = 0,
        },
    };

    for (input) |c| {
        if (parseCharacter(c, &state)) |command| {
            try commands.append(command);
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
        '\'' => Command{
            .MotionOnly = CommandData{
                .motion = Motion{
                    .ToMarkLine = null,
                },
                .register = null,
            },
        },
        '`' => Command{
            .MotionOnly = CommandData{
                .motion = Motion{
                    .ToMarkPosition = null,
                },
                .register = null,
            },
        },
        'l' => Command{
            .MotionOnly = CommandData{
                .motion = Motion{ .ForwardsCharacter = range orelse 1 },
                .register = register,
            },
        },
        'h' => Command{
            .MotionOnly = CommandData{
                .motion = Motion{ .BackwardsCharacter = range orelse 1 },
                .register = register,
            },
        },
        'G' => Command{
            .MotionOnly = CommandData{
                .motion = Motion{ .UntilEndOfFile = range orelse 0 },
                .register = register,
            },
        },
        'J' => Command{ .BringLineUp = range orelse 1 },
        'u' => Command.Undo,
        'i' => Command{ .EnterInsertMode = range orelse 1 },
        's' => Command{
            .ReplaceInsert = ReplaceInsertData{
                .range = range orelse 1,
                .register = register,
            },
        },
        'o' => Command{ .InsertDownwards = range orelse 1 },
        'O' => Command{ .InsertUpwards = range orelse 1 },
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
        'l' => Motion{ .ForwardsCharacter = builder_data.range orelse 1 },
        'h' => Motion{ .BackwardsCharacter = builder_data.range orelse 1 },
        '`' => Motion{ .ToMarkPosition = null },
        '\'' => Motion{ .ToMarkLine = null },
        'i' => Motion{ .Inside = null },
        's' => Motion{ .Surrounding = null },
        'G' => Motion{ .UntilEndOfFile = builder_data.range orelse 0 },
        '%' => Motion.ToMatching,
        else => std.debug.panic("unsupported motion: {c}\n", character),
    };
}

fn gCommandFromKey(character: u8, state: *State) ?Command {
    return switch (state.*) {
        .WaitingForGCommand => |*builder_data| outer: {
            switch (character) {
                'g' => {
                    switch (builder_data.command) {
                        .Delete, .Yank, .Change, .Comment => |*command_data| {
                            command_data.motion = Motion{
                                .UntilBeginningOfFile = builder_data.range orelse 0,
                            };
                        },
                        .Unset => {
                            builder_data.command = Command{
                                .MotionOnly = CommandData{
                                    .motion = Motion{
                                        .UntilBeginningOfFile = builder_data.range orelse 0,
                                    },
                                    .register = builder_data.register,
                                },
                            };
                        },
                        .MotionOnly,
                        .SetMark,
                        .PasteForwards,
                        .PasteBackwards,
                        .BringLineUp,
                        .Undo,
                        .EnterInsertMode,
                        .Insert,
                        .ExitInsertMode,
                        .ReplaceInsert,
                        .InsertDownwards,
                        .InsertUpwards,
                        .ScrollTop,
                        .ScrollCenter,
                        .ScrollBottom,
                        => {
                            std.debug.panic("invalid g command state: {}\n", builder_data.command);
                        },
                    }

                    break :outer builder_data.command;
                },
                'c' => {
                    builder_data.command = Command{
                        .Comment = CommandData{
                            .motion = Motion.Unset,
                            .register = null,
                        },
                    };
                    state.* = State{ .WaitingForMotion = builder_data.* };

                    break :outer null;
                },
                else => std.debug.panic("unsupported G command: {c}\n", character),
            }
        },
        else => unreachable,
    };
}

fn zCommandFromKey(character: u8, state: *State) ?Command {
    return switch (state.*) {
        .WaitingForZCommand => |*builder_data| outer: {
            switch (character) {
                't' => {
                    state.* = State{ .Start = CommandBuilderData{} };

                    break :outer Command{ .ScrollTop = undefined };
                },
                'z' => {
                    state.* = State{ .Start = CommandBuilderData{} };

                    break :outer Command{ .ScrollCenter = undefined };
                },
                'b' => {
                    state.* = State{ .Start = CommandBuilderData{} };

                    break :outer Command{ .ScrollBottom = undefined };
                },
                else => std.debug.panic("unsupported G command: {c}\n", character),
            }
        },
        else => unreachable,
    };
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
    testing.expect(std.meta.activeTag(third_command) == Command.MotionOnly);
    switch (third_command) {
        .MotionOnly => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.ToMarkLine);
            switch (command_data.motion) {
                .ToMarkLine => |mark| testing.expectEqual(mark, 'a'),
                else => unreachable,
            }
        },
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
    testing.expect(std.meta.activeTag(third_command) == Command.MotionOnly);
    switch (third_command) {
        .MotionOnly => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.ToMarkPosition);
            switch (command_data.motion) {
                .ToMarkPosition => |mark| testing.expectEqual(mark, 'a'),
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`d`a` = 'delete until mark a's position'" {
    const input = "d`a"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.ToMarkPosition);
            switch (command_data.motion) {
                .ToMarkPosition => |mark| {
                    testing.expectEqual(mark, 'a');
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`d'a` = 'delete until mark a's line'" {
    const input = "d'a"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.ToMarkLine);
            switch (command_data.motion) {
                .ToMarkLine => |mark| {
                    testing.expectEqual(mark, 'a');
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`9l22h` = 'go forward 9 characters, go back 22 characters'" {
    const input = "9l22h"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 2);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    const second_command = command_slice[1];
    testing.expect(std.meta.activeTag(first_command) == Command.MotionOnly);
    switch (first_command) {
        .MotionOnly => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.ForwardsCharacter);
            switch (command_data.motion) {
                .ForwardsCharacter => |characters| {
                    testing.expectEqual(characters, 9);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
    switch (second_command) {
        .MotionOnly => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.BackwardsCharacter);
            switch (command_data.motion) {
                .BackwardsCharacter => |characters| {
                    testing.expectEqual(characters, 22);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`\"aci\"` = 'change inside double quotes and save old content to register a'" {
    const input = "\"aci\""[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Change);
    switch (first_command) {
        .Change => |command_data| {
            testing.expectEqual(command_data.register, 'a');
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.Inside);
            switch (command_data.motion) {
                .Inside => |character| {
                    testing.expectEqual(character, '\"');
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`\"adi\"15k\"a2p` = 'delete inside double quotes into register a, move up, paste from it'" {
    const input = "\"adi\"15k\"a2p"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 3);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    const second_command = command_slice[1];
    const third_command = command_slice[2];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expectEqual(command_data.register, 'a');
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.Inside);
            switch (command_data.motion) {
                .Inside => |character| {
                    testing.expectEqual(character, '\"');
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
    testing.expect(std.meta.activeTag(second_command) == Command.MotionOnly);
    switch (second_command) {
        .MotionOnly => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UpwardsLines);
            switch (command_data.motion) {
                .UpwardsLines => |lines| {
                    testing.expectEqual(lines, 15);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
    testing.expect(std.meta.activeTag(third_command) == Command.PasteForwards);
    switch (third_command) {
        .PasteForwards => |paste_data| {
            testing.expectEqual(paste_data.register, 'a');
            testing.expectEqual(paste_data.range, 2);
        },
        else => unreachable,
    }
}

test "`cs\"` = 'change surrounding double quotes" {
    const input = "cs\""[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Change);
    switch (first_command) {
        .Change => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.Surrounding);
            switch (command_data.motion) {
                .Surrounding => |character| {
                    testing.expectEqual(character, '\"');
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`ds\"` = 'delete surrounding double quotes" {
    const input = "ds\""[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.Surrounding);
            switch (command_data.motion) {
                .Surrounding => |character| {
                    testing.expectEqual(character, '\"');
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`dG` = 'delete until end of file'" {
    const input = "dG"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UntilEndOfFile);
            switch (command_data.motion) {
                .UntilEndOfFile => |line_number| {
                    testing.expectEqual(line_number, 0);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`G` = 'go to end of file'" {
    const input = "G"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.MotionOnly);
    switch (first_command) {
        .MotionOnly => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UntilEndOfFile);
            switch (command_data.motion) {
                .UntilEndOfFile => |line_number| {
                    testing.expectEqual(line_number, 0);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`15G` = 'go to end of file'" {
    const input = "15G"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.MotionOnly);
    switch (first_command) {
        .MotionOnly => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UntilEndOfFile);
            switch (command_data.motion) {
                .UntilEndOfFile => |line_number| {
                    testing.expectEqual(line_number, 15);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`\"ad15G` = 'delete until line 15 of file into register a'" {
    const input = "\"ad15G"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expectEqual(command_data.register, 'a');
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UntilEndOfFile);
            switch (command_data.motion) {
                .UntilEndOfFile => |line_number| {
                    testing.expectEqual(line_number, 15);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`d15G` = 'delete until line 15 of file'" {
    const input = "d15G"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UntilEndOfFile);
            switch (command_data.motion) {
                .UntilEndOfFile => |line_number| {
                    testing.expectEqual(line_number, 15);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`dgg` = 'delete until beginning of file'" {
    const input = "dgg"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UntilBeginningOfFile);
            switch (command_data.motion) {
                .UntilBeginningOfFile => |line_number| {
                    testing.expectEqual(line_number, 0);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`gg` = 'go to beginning of file'" {
    const input = "gg"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.MotionOnly);
    switch (first_command) {
        .MotionOnly => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UntilBeginningOfFile);
            switch (command_data.motion) {
                .UntilBeginningOfFile => |line_number| {
                    testing.expectEqual(line_number, 0);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`15gg` = 'go to line 15 of file'" {
    const input = "15gg"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.MotionOnly);
    switch (first_command) {
        .MotionOnly => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UntilBeginningOfFile);
            switch (command_data.motion) {
                .UntilBeginningOfFile => |line_number| {
                    testing.expectEqual(line_number, 15);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`\"ad15gg` = 'delete until line 15 of file into register a'" {
    const input = "\"ad15gg"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expectEqual(command_data.register, 'a');
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UntilBeginningOfFile);
            switch (command_data.motion) {
                .UntilBeginningOfFile => |line_number| {
                    testing.expectEqual(line_number, 15);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`d15gg` = 'delete until line 15 of file'" {
    const input = "d15gg"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Delete);
    switch (first_command) {
        .Delete => |command_data| {
            testing.expectEqual(command_data.register, null);
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UntilBeginningOfFile);
            switch (command_data.motion) {
                .UntilBeginningOfFile => |line_number| {
                    testing.expectEqual(line_number, 15);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`gc20j` = 'comment downwards 20 lines'" {
    const input = "gc20j"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Comment);
    switch (first_command) {
        .Comment => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.DownwardsLines);
            switch (command_data.motion) {
                .DownwardsLines => |line_number| {
                    testing.expectEqual(line_number, 20);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`20gcj` = 'comment downwards 20 lines'" {
    const input = "20gcj"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Comment);
    switch (first_command) {
        .Comment => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.DownwardsLines);
            switch (command_data.motion) {
                .DownwardsLines => |line_number| {
                    testing.expectEqual(line_number, 20);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`gc%` = 'comment until matching token'" {
    const input = "gc%"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Comment);
    switch (first_command) {
        .Comment => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.ToMatching);
        },
        else => unreachable,
    }
}

test "`J` = 'bring line up'" {
    const input = "J"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.BringLineUp);
    switch (first_command) {
        .BringLineUp => |lines| {
            testing.expectEqual(lines, 1);
        },
        else => unreachable,
    }
}

test "`25J` = 'bring line up'" {
    const input = "25J"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.BringLineUp);
    switch (first_command) {
        .BringLineUp => |lines| {
            testing.expectEqual(lines, 25);
        },
        else => unreachable,
    }
}

test "`u` = 'undo'" {
    const input = "u"[0..];
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Undo);
}

test "`i` = 'enter insert mode' & state is modified to be in insert mode after" {
    const input = 'i';
    var state = State{ .Start = CommandBuilderData{} };
    const maybeCommand = parseCharacter(input, &state);
    if (maybeCommand) |command| {
        testing.expect(std.meta.activeTag(state) == State.InInsertMode);
        testing.expect(std.meta.activeTag(command) == Command.EnterInsertMode);
    } else {
        std.debug.panic("No command when expecting one.");
    }
}

test "`iC-[` = 'enter insert mode, then exit it'" {
    const input1 = 'i';
    var state = State{ .Start = CommandBuilderData{} };
    const maybeCommand1 = parseCharacter(input1, &state);
    if (maybeCommand1) |command| {
        testing.expect(std.meta.activeTag(state) == State.InInsertMode);
        testing.expect(std.meta.activeTag(command) == Command.EnterInsertMode);
    } else {
        std.debug.panic("No command when expecting one.");
    }
    const maybeCommand2 = parseCharacter(ESCAPE_KEY, &state);
    if (maybeCommand2) |command| {
        testing.expect(std.meta.activeTag(state) == State.Start);
        testing.expect(std.meta.activeTag(command) == Command.ExitInsertMode);
    } else {
        std.debug.panic("No command when expecting one.");
    }
}

test "`igaf%C-[` = 'enter insert mode, then exit it'" {
    const input = "igaf%\x1b";
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 6);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.EnterInsertMode);
    switch (first_command) {
        .EnterInsertMode => |range| {
            testing.expectEqual(range, 1);
        },
        else => unreachable,
    }
    const insert_commands = command_slice[1..(command_slice.len - 1)];
    for (insert_commands) |insert_command, index| {
        testing.expect(std.meta.activeTag(insert_command) == Command.Insert);
        switch (insert_command) {
            .Insert => |character| {
                testing.expectEqual(character, input[index + 1]);
            },
            else => unreachable,
        }
    }
    const last_command = command_slice[5];
    testing.expect(std.meta.activeTag(last_command) == Command.ExitInsertMode);
}

test "`sgaf%C-[` = 'replace current character, then exit insert mode'" {
    const input = "sgaf%\x1b";
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 6);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.ReplaceInsert);
    switch (first_command) {
        .ReplaceInsert => |command_data| {
            testing.expectEqual(command_data.range, 1);
            testing.expectEqual(command_data.register, null);
        },
        else => unreachable,
    }
    const insert_commands = command_slice[1..(command_slice.len - 1)];
    for (insert_commands) |insert_command, index| {
        testing.expect(std.meta.activeTag(insert_command) == Command.Insert);
        switch (insert_command) {
            .Insert => |character| {
                testing.expectEqual(character, input[index + 1]);
            },
            else => unreachable,
        }
    }
    const last_command = command_slice[5];
    testing.expect(std.meta.activeTag(last_command) == Command.ExitInsertMode);
}

test "`3sgaf%C-[` = 'replace three characters, then exit insert mode'" {
    const input = "3sgaf%\x1b";
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 6);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.ReplaceInsert);
    switch (first_command) {
        .ReplaceInsert => |command_data| {
            testing.expectEqual(command_data.range, 3);
            testing.expectEqual(command_data.register, null);
        },
        else => unreachable,
    }
    const insert_commands = command_slice[1..(command_slice.len - 1)];
    for (insert_commands) |insert_command, index| {
        testing.expect(std.meta.activeTag(insert_command) == Command.Insert);
        switch (insert_command) {
            .Insert => |character| {
                // +2 because of `3s`
                testing.expectEqual(character, input[index + 2]);
            },
            else => unreachable,
        }
    }
    const last_command = command_slice[5];
    testing.expect(std.meta.activeTag(last_command) == Command.ExitInsertMode);
}

test "`\"a3sgaf%C-[` = 'replace three characters, then exit insert mode'" {
    const input = "\"a3sgaf%\x1b";
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 6);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.ReplaceInsert);
    switch (first_command) {
        .ReplaceInsert => |command_data| {
            testing.expectEqual(command_data.range, 3);
            testing.expectEqual(command_data.register, 'a');
        },
        else => unreachable,
    }
    const insert_commands = command_slice[1..(command_slice.len - 1)];
    for (insert_commands) |insert_command, index| {
        testing.expect(std.meta.activeTag(insert_command) == Command.Insert);
        switch (insert_command) {
            .Insert => |character| {
                // +4 because of `"a3s`
                testing.expectEqual(character, input[index + 4]);
            },
            else => unreachable,
        }
    }
    const last_command = command_slice[5];
    testing.expect(std.meta.activeTag(last_command) == Command.ExitInsertMode);
}

test "`ogaf%C-[` = 'insert on new line downwards, then exit insert mode'" {
    const input = "ogaf%\x1b";
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 6);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.InsertDownwards);
    switch (first_command) {
        .InsertDownwards => |range| {
            testing.expectEqual(range, 1);
        },
        else => unreachable,
    }
    const insert_commands = command_slice[1..(command_slice.len - 1)];
    for (insert_commands) |insert_command, index| {
        testing.expect(std.meta.activeTag(insert_command) == Command.Insert);
        switch (insert_command) {
            .Insert => |character| {
                testing.expectEqual(character, input[index + 1]);
            },
            else => unreachable,
        }
    }
    const last_command = command_slice[5];
    testing.expect(std.meta.activeTag(last_command) == Command.ExitInsertMode);
}

test "`265ogaf%C-[` = 'insert on new line downwards, then exit insert mode'" {
    const input = "265ogaf%\x1b";
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 6);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.InsertDownwards);
    switch (first_command) {
        .InsertDownwards => |range| {
            testing.expectEqual(range, 265);
        },
        else => unreachable,
    }
    const insert_commands = command_slice[1..(command_slice.len - 1)];
    for (insert_commands) |insert_command, index| {
        testing.expect(std.meta.activeTag(insert_command) == Command.Insert);
        switch (insert_command) {
            .Insert => |character| {
                // +4 because of `265o`
                testing.expectEqual(character, input[index + 4]);
            },
            else => unreachable,
        }
    }
    const last_command = command_slice[5];
    testing.expect(std.meta.activeTag(last_command) == Command.ExitInsertMode);
}

test "`Ogaf%C-[` = 'insert on new line upwards, then exit insert mode'" {
    const input = "Ogaf%\x1b";
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 6);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.InsertUpwards);
    switch (first_command) {
        .InsertUpwards => |range| {
            testing.expectEqual(range, 1);
        },
        else => unreachable,
    }
    const insert_commands = command_slice[1..(command_slice.len - 1)];
    for (insert_commands) |insert_command, index| {
        testing.expect(std.meta.activeTag(insert_command) == Command.Insert);
        switch (insert_command) {
            .Insert => |character| {
                testing.expectEqual(character, input[index + 1]);
            },
            else => unreachable,
        }
    }
    const last_command = command_slice[5];
    testing.expect(std.meta.activeTag(last_command) == Command.ExitInsertMode);
}

test "`15Ogaf%C-[` = 'insert on new line upwards, then exit insert mode'" {
    const input = "15Ogaf%\x1b";
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 6);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.InsertUpwards);
    switch (first_command) {
        .InsertUpwards => |range| {
            testing.expectEqual(range, 15);
        },
        else => unreachable,
    }
    const insert_commands = command_slice[1..(command_slice.len - 1)];
    for (insert_commands) |insert_command, index| {
        testing.expect(std.meta.activeTag(insert_command) == Command.Insert);
        switch (insert_command) {
            .Insert => |character| {
                // +3 because of `15O`
                testing.expectEqual(character, input[index + 3]);
            },
            else => unreachable,
        }
    }
    const last_command = command_slice[5];
    testing.expect(std.meta.activeTag(last_command) == Command.ExitInsertMode);
}

test "`zt` = 'scroll view so that cursor is at top'" {
    const input = "zt";
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.ScrollTop);
}

test "`zz` = 'scroll view so that cursor is at center'" {
    const input = "zz";
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.ScrollCenter);
}

test "`zb` = 'scroll view so that cursor is at bottom'" {
    const input = "zb";
    const commands = try parseInput(direct_allocator, input);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.ScrollBottom);
}

pub fn runTests() void {}

const ESCAPE_KEY = '\x1b';
