const std = @import("std");
const mem = std.mem;
const ArrayList = std.ArrayList;

/// Represents a key press. Unless otherwise specified all modifier keys are assumed to be `false`.
pub const Key = struct {
    key_code: u8,
    left_control: bool = false,
    left_alt: bool = false,
    right_control: bool = false,
    right_alt: bool = false,
};

/// Represents a vim command. These are to be interpreted as needed by whichever runtime is
/// interested. For naked motion commands (possibly with associated range data), there is a
/// `MotionOnly` command.
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
    Redo,
    EnterInsertMode: u32,
    Insert: u8,
    ExitInsertMode,
    ReplaceInsert: ReplaceInsertData,
    // @NOTE: `Insert{Upwards,Downwards}` are actually supposed to insert on all lines when using
    // ranges, but the current insert mode doesn't handle this (2019-12-01). It could be solved on
    // the client interpretation side via spawning multiple cursors as a response to the range
    // attribute, but punting it to the client seems awkward. With that said, this is not a use case
    // that I'm going to necessarily miss if it never gets implemented...
    InsertDownwards: u32,
    InsertUpwards: u32,
    ScrollTop,
    ScrollCenter,
    ScrollBottom,
    BeginMacro: u8,
    EndMacro: EndMacroData,
};

const EndMacroData = struct {
    slot: u8,
    commands: []Command,
};

/// Represents a motion that is usually attached to a `Command`.
pub const Motion = union(enum) {
    Unset,
    UntilEndOfWord: u32,
    UntilNextWord: u32,
    UntilStartOfPreviousWord: u32,
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

pub const CommandData = struct {
    motion: Motion,
    register: ?u8,
};

pub const PasteData = struct {
    register: ?u8,
    range: ?u32,
};

pub const ReplaceInsertData = struct {
    register: ?u8,
    range: u32,
};

/// Represents the current state of the vim mode; can be passed to `handleKey` in order to get a new
/// state as well as a command if one can be generated from the passed `Key` in that `State`.
pub const State = union(enum) {
    Start: CommandBuilderData,
    InInsertMode: InsertModeData,
    WaitingForMotion: CommandBuilderData,
    WaitingForTarget: CommandBuilderData,
    WaitingForRegister: CommandBuilderData,
    WaitingForMark: CommandBuilderData,
    WaitingForGCommand: CommandBuilderData,
    WaitingForZCommand: CommandBuilderData,
    WaitingForSlot: CommandBuilderData,
    RecordingMacro: RecordingMacroData,

    pub fn start() State {
        return State{ .Start = CommandBuilderData{} };
    }
};

const RecordingMacroData = struct {
    slot: u8,
    state: *State,
    commands: ArrayList(Command),
};

pub const CommandBuilderData = struct {
    range: ?u32 = null,
    range_modifiers: u32 = 0,
    register: ?u8 = null,
    command: Command = Command.Unset,
};

pub const InsertModeData = struct {
    range: ?u32 = null,
    range_modifiers: u32 = 0,
};

const HandleKeyError = error{
    OutOfMemory,
    UnknownMacroSlot,
    NoCommandWhenWaitingForMotion,
    NoCommandWhenWaitingForTarget,
    UnimplementedMotion,
    UnsupportedLeftControlCommand,
    UnsupportedCommand,
    UnsupportedMotion,
    UnsupportedGCommand,
    UnsupportedZCommand,
    UnexpectedStartKey,
    UnknownRegister,
    InvalidWaitingForMarkCommand,
    InvalidWaitingForMarkMotion,
    InvalidWaitingForMotionCommand,
    InvalidWaitingForTargetMotion,
    InvalidWaitingForTargetCommand,
    InvalidGCommandState,
};

/// Handles a key for a given input state.
/// Because a list of commands can be accumulated across several calls of this an allocator is
/// needed for the macro data that is being recorded. If a `EndMacro` command is returned the
/// caller is responsible for freeing the associated command list when they no longer care about it.
pub fn handleKey(allocator: *mem.Allocator, key: Key, state: *State) HandleKeyError!?Command {
    return switch (state.*) {
        State.Start => |*builder_data| try handleStart(builder_data, state, key),

        State.WaitingForRegister => |*builder_data| {
            switch (key.key_code) {
                'a'...'z', 'A'...'Z', '+', '*' => {
                    builder_data.register = key.key_code;
                    state.* = State{ .Start = builder_data.* };

                    return null;
                },
                else => {
                    debugPanic("unknown register: {}\n", .{key.key_code});

                    return error.UnknownRegister;
                },
            }
        },

        .WaitingForMark => |*builder_data| try handleWaitingForMark(builder_data, state, key),

        .WaitingForSlot => |*builder_data| try handleWaitingForSlot(
            allocator,
            builder_data,
            state,
            key,
        ),

        .RecordingMacro => |*in_macro_data| {
            switch (key.key_code) {
                'q' => {
                    const command = Command{
                        .EndMacro = EndMacroData{
                            .slot = in_macro_data.slot,
                            .commands = in_macro_data.commands.items,
                        },
                    };
                    // We destroy only the intermediate macro data state because it's internal.
                    // The command list that has been recorded will have to be freed by the user.
                    allocator.destroy(in_macro_data.state);
                    state.* = State.start();

                    return command;
                },
                else => {
                    const command = try handleKey(allocator, key, in_macro_data.state);
                    if (command) |c| {
                        try in_macro_data.commands.append(c);
                    }

                    return command;
                },
            }
        },

        State.WaitingForTarget => |*builder_data| try handleWaitingForTarget(
            builder_data,
            state,
            key,
        ),

        State.WaitingForMotion => |*builder_data| try handleWaitingForMotion(
            builder_data,
            state,
            key,
        ),

        State.WaitingForGCommand => |*builder_data| {
            return try gCommandFromKey(key, state);
        },

        State.WaitingForZCommand => |*builder_data| {
            return try zCommandFromKey(key, state);
        },

        State.InInsertMode => |*insert_mode_data| {
            return switch (key.key_code) {
                ESCAPE_KEY.key_code => i: {
                    const command = Command{ .ExitInsertMode = undefined };
                    state.* = State.start();

                    break :i command;
                },
                else => |character| i: {
                    break :i Command{ .Insert = character };
                },
            };
        },
    };
}

pub fn handleKeys(allocator: *mem.Allocator, keys: []const Key, state: *State) !ArrayList(Command) {
    var commands = ArrayList(Command).init(allocator);
    errdefer commands.deinit();

    for (keys) |k| {
        if (try handleKey(allocator, k, state)) |command| {
            try commands.append(command);
        }
    }

    return commands;
}

fn commandFromKey(key: Key, register: ?u8, range: ?u32) !Command {
    if (key.left_control) {
        return switch (key.key_code) {
            'r' => Command{ .Redo = undefined },
            else => err: {
                debugPanic("unsupported command key with left control: {}\n", .{key.key_code});

                break :err error.UnsupportedLeftControlCommand;
            },
        };
    }

    return switch (key.key_code) {
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
        'w' => Command{
            .MotionOnly = CommandData{
                .motion = Motion{ .UntilNextWord = range orelse 1 },
                .register = register,
            },
        },
        'b' => Command{
            .MotionOnly = CommandData{
                .motion = Motion{ .UntilStartOfPreviousWord = range orelse 1 },
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
        'u' => Command{ .Undo = undefined },
        'i' => Command{ .EnterInsertMode = range orelse 1 },
        's' => Command{
            .ReplaceInsert = ReplaceInsertData{
                .range = range orelse 1,
                .register = register,
            },
        },
        'o' => Command{ .InsertDownwards = range orelse 1 },
        'O' => Command{ .InsertUpwards = range orelse 1 },
        else => {
            debugPanic("unsupported command key: {}\n", .{key.key_code});

            return error.UnsupportedCommand;
        },
    };
}

fn motionFromKey(key: Key, builder_data: CommandBuilderData) !Motion {
    return switch (key.key_code) {
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
        '0' => Motion{ .UntilColumnZero = undefined },
        'l' => Motion{ .ForwardsCharacter = builder_data.range orelse 1 },
        'h' => Motion{ .BackwardsCharacter = builder_data.range orelse 1 },
        '`' => Motion{ .ToMarkPosition = null },
        '\'' => Motion{ .ToMarkLine = null },
        'i' => Motion{ .Inside = null },
        's' => Motion{ .Surrounding = null },
        'G' => Motion{ .UntilEndOfFile = builder_data.range orelse 0 },
        '%' => Motion{ .ToMatching = undefined },
        else => {
            debugPanic("unsupported motion: {c}\n", .{key.key_code});

            return error.UnsupportedMotion;
        },
    };
}

fn gCommandFromKey(key: Key, state: *State) !?Command {
    return switch (state.*) {
        .WaitingForGCommand => |*builder_data| outer: {
            switch (key.key_code) {
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
                        .Redo,
                        .EnterInsertMode,
                        .Insert,
                        .ExitInsertMode,
                        .ReplaceInsert,
                        .InsertDownwards,
                        .InsertUpwards,
                        .ScrollTop,
                        .ScrollCenter,
                        .ScrollBottom,
                        .BeginMacro,
                        .EndMacro,
                        => {
                            debugPanic("invalid g command state: {}\n", .{builder_data.command});

                            return error.InvalidGCommandState;
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
                else => {
                    debugPanic("unsupported G command: {c}\n", .{key.key_code});

                    return error.UnsupportedGCommand;
                },
            }
        },
        else => unreachable,
    };
}

fn zCommandFromKey(key: Key, state: *State) !?Command {
    return switch (state.*) {
        .WaitingForZCommand => |*builder_data| outer: {
            switch (key.key_code) {
                't' => {
                    state.* = State.start();

                    break :outer Command{ .ScrollTop = undefined };
                },
                'z' => {
                    state.* = State.start();

                    break :outer Command{ .ScrollCenter = undefined };
                },
                'b' => {
                    state.* = State.start();

                    break :outer Command{ .ScrollBottom = undefined };
                },
                else => {
                    debugPanic("unsupported Z command: {c}\n", .{key.key_code});
                    return error.UnsupportedZCommand;
                },
            }
        },
        else => unreachable,
    };
}

fn handleStart(builder_data: *CommandBuilderData, state: *State, key: Key) !?Command {
    switch (key.key_code) {
        '"' => {
            state.* = State{ .WaitingForRegister = builder_data.* };

            return null;
        },
        '0'...'9' => {
            const numeric_value = key.key_code - '0';
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
            builder_data.command = try commandFromKey(
                key,
                builder_data.register,
                builder_data.range,
            );
            state.* = State{ .WaitingForMotion = builder_data.* };

            return null;
        },
        'm', '\'', '`' => {
            builder_data.command = try commandFromKey(
                key,
                builder_data.register,
                builder_data.range,
            );
            state.* = State{ .WaitingForMark = builder_data.* };

            return null;
        },
        'p', 'P', 'j', 'k', '$', '^', '{', '}', 'l', 'h', 'G', 'J', 'u', 'w', 'b' => {
            const command = try commandFromKey(
                key,
                builder_data.register,
                builder_data.range,
            );
            state.* = State.start();

            return command;
        },
        'f', 'F', 't', 'T' => {
            builder_data.command = try commandFromKey(
                key,
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
            const command = try commandFromKey(key, builder_data.register, builder_data.range);
            state.* = State{ .InInsertMode = InsertModeData{} };

            return command;
        },
        'r' => {
            const command = try commandFromKey(key, builder_data.register, builder_data.range);
            switch (command) {
                Command.Redo => {
                    state.* = State.start();

                    return command;
                },
                else => {
                    return null;
                },
            }
        },
        'q' => {
            state.* = State{ .WaitingForSlot = builder_data.* };

            return null;
        },

        // @TODO: add 'C' support
        // Needs to support range + registers

        // @TODO: add 'D' support
        // Needs to support range + registers
        // Interestingly VSCodeVim does not support ranges for `D` though Vim does

        else => {
            debugPanic(
                "Not expecting character '{c}', waiting for command or range modifier",
                .{key.key_code},
            );

            return error.UnexpectedStartKey;
        },
    }
}

fn handleWaitingForMark(builder_data: *CommandBuilderData, state: *State, key: Key) !?Command {
    return switch (builder_data.command) {
        .SetMark => |*mark| {
            mark.* = key.key_code;
            const command = builder_data.command;
            state.* = State.start();

            return command;
        },
        .Yank, .Delete, .Change, .MotionOnly, .Comment => |*command_data| {
            switch (command_data.motion) {
                .ToMarkLine, .ToMarkPosition => |*mark| {
                    mark.* = key.key_code;
                    const command = builder_data.command;
                    state.* = State.start();

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
                .UntilStartOfPreviousWord,
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
                    debugPanic(
                        "invalid motion for `WaitingForMark`: {}\n",
                        .{command_data.motion},
                    );

                    return error.InvalidWaitingForMarkMotion;
                },
            }
        },
        .PasteForwards,
        .PasteBackwards,
        .Unset,
        .BringLineUp,
        .Undo,
        .Redo,
        .EnterInsertMode,
        .Insert,
        .ExitInsertMode,
        .ReplaceInsert,
        .InsertDownwards,
        .InsertUpwards,
        .ScrollTop,
        .ScrollCenter,
        .ScrollBottom,
        .BeginMacro,
        .EndMacro,
        => {
            debugPanic(
                "Invalid command for `WaitingForMark`: {}\n",
                .{builder_data.command},
            );

            return error.InvalidWaitingForMarkCommand;
        },
    };
}

fn handleWaitingForTarget(builder_data: *CommandBuilderData, state: *State, key: Key) !?Command {
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
                    target.* = key.key_code;
                    const command = builder_data.command;
                    state.* = State.start();

                    return command;
                },
                .Unset,
                .UntilEndOfWord,
                .UntilNextWord,
                .UntilStartOfPreviousWord,
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
                => {
                    debugPanic(
                        "non-target motion waiting for target: {}\n",
                        .{command_data.motion},
                    );

                    return error.InvalidWaitingForTargetMotion;
                },
            }
        },
        .PasteForwards,
        .PasteBackwards,
        .SetMark,
        .BringLineUp,
        .Undo,
        .Redo,
        .EnterInsertMode,
        .Insert,
        .ExitInsertMode,
        .ReplaceInsert,
        .InsertDownwards,
        .InsertUpwards,
        .ScrollTop,
        .ScrollCenter,
        .ScrollBottom,
        .BeginMacro,
        .EndMacro,
        => {
            debugPanic(
                "invalid command for `WaitingForTarget`: {}\n",
                .{builder_data.command},
            );

            return error.InvalidWaitingForTargetCommand;
        },
        .Unset => {
            debugPanic("no command set when waiting for target", .{});

            return error.NoCommandWhenWaitingForTarget;
        },
    }
}

fn handleWaitingForMotion(builder_data: *CommandBuilderData, state: *State, key: Key) !?Command {
    switch (builder_data.command) {
        .Delete, .Yank, .Change, .Comment => |*command_data| {
            switch (key.key_code) {
                '1'...'9' => {
                    const numeric_value = key.key_code - '0';
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
                        command_data.motion = try motionFromKey(key, builder_data.*);
                        const command = builder_data.command;
                        state.* = State.start();

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
                    command_data.motion = try motionFromKey(key, builder_data.*);
                    const command = builder_data.command;
                    state.* = State.start();

                    return command;
                },
                'f', 'F', 't', 'T', 'i', 's' => {
                    command_data.motion = try motionFromKey(key, builder_data.*);
                    state.* = State{ .WaitingForTarget = builder_data.* };

                    return null;
                },
                '`', '\'' => {
                    command_data.motion = try motionFromKey(key, builder_data.*);
                    state.* = State{ .WaitingForMark = builder_data.* };

                    return null;
                },
                'g' => {
                    state.* = State{ .WaitingForGCommand = builder_data.* };

                    return null;
                },
                else => {
                    debugPanic("unimplemented motion: {c}\n", .{key.key_code});

                    return error.UnimplementedMotion;
                },
            }
        },
        .PasteForwards,
        .PasteBackwards,
        .MotionOnly,
        .SetMark,
        .BringLineUp,
        .Undo,
        .Redo,
        .EnterInsertMode,
        .Insert,
        .ExitInsertMode,
        .ReplaceInsert,
        .InsertDownwards,
        .InsertUpwards,
        .ScrollTop,
        .ScrollCenter,
        .ScrollBottom,
        .BeginMacro,
        .EndMacro,
        => {
            debugPanic(
                "invalid command for `WaitingForMotion`: {}\n",
                .{builder_data.command},
            );

            return error.InvalidWaitingForMotionCommand;
        },
        .Unset => {
            debugPanic("no command when waiting for motion", .{});

            return error.NoCommandWhenWaitingForMotion;
        },
    }
}

fn handleWaitingForSlot(
    allocator: *mem.Allocator,
    builder_data: *CommandBuilderData,
    state: *State,
    key: Key,
) !?Command {
    switch (key.key_code) {
        'a'...'z', 'A'...'Z', '0'...'9' => {
            const command = Command{ .BeginMacro = key.key_code };
            var macro_state = try allocator.create(State);
            var commands = ArrayList(Command).init(allocator);
            macro_state.* = State.start();
            state.* = State{
                .RecordingMacro = RecordingMacroData{
                    .slot = key.key_code,
                    .state = macro_state,
                    .commands = commands,
                },
            };

            return command;
        },
        else => {
            debugPanic("unknown macro slot: {}\n", .{key.key_code});

            return error.UnknownMacroSlot;
        },
    }
}

pub const ESCAPE_KEY = Key{ .key_code = '\x1b' };

fn debugPanic(comptime format: []const u8, args: anytype) void {
    switch (std.builtin.mode) {
        .Debug => std.debug.panic(format, args),
        else => {},
    }
}
