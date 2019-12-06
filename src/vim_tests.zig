const std = @import("std");
const direct_allocator = std.heap.direct_allocator;
const testing = std.testing;

const vim = @import("./vim.zig");
const Key = vim.Key;
const State = vim.State;
const CommandBuilderData = vim.CommandBuilderData;
const Command = vim.Command;
const Motion = vim.Motion;

fn stringToKeys(comptime size: usize, string: *const [size:0]u8) [size]Key {
    var keys: [size]Key = undefined;
    for (string) |character, index| {
        keys[index] = characterToKey(character);
    }

    return keys;
}

fn characterToKey(character: u8) Key {
    return .{ .key_code = character };
}

test "`dd` creates a delete command" {
    const input = "dd";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "dddd";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "ddde";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "dw";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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

test "`w` = 'move forward one word'" {
    const input = "w";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.MotionOnly);
    switch (first_command) {
        .MotionOnly => |command_data| {
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

test "`b` = 'move back one word'" {
    const input = "b";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.MotionOnly);
    switch (first_command) {
        .MotionOnly => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UntilPreviousWord);
            switch (command_data.motion) {
                .UntilPreviousWord => |words| {
                    testing.expectEqual(words, 1);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`51w` = 'move forward 51 words'" {
    const input = "51w";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.MotionOnly);
    switch (first_command) {
        .MotionOnly => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UntilNextWord);
            switch (command_data.motion) {
                .UntilNextWord => |words| {
                    testing.expectEqual(words, 51);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`51b` = 'move back 51 words'" {
    const input = "51b";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.MotionOnly);
    switch (first_command) {
        .MotionOnly => |command_data| {
            testing.expect(std.meta.activeTag(command_data.motion) == Motion.UntilPreviousWord);
            switch (command_data.motion) {
                .UntilPreviousWord => |words| {
                    testing.expectEqual(words, 51);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

test "`dj` = 'delete one line downwards'" {
    const input = "dj";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "dk";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "5dj";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "5dk";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "5dd";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "52dd";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "52dj";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "5232dj";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "5232dj2301dk";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "5232yy";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "522yj201yk";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "df)";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "dF)";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "dt)";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "dT)";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "\"add";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "\"+5dj";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "p";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "\"a3P";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "d$";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "d^";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "cc";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "cfe";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "\"*cT$";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "15c$";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "15j";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "14$";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "3f\"";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "150F(";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "2T(";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "15t)";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "\"u2d}";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "\"o15y{";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "}2{";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "\"ay0\"a3p";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "maj'a";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "maj`a";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "d`a";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "d'a";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "9l22h";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "\"aci\"";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "\"adi\"15k\"a2p";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "cs\"";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "ds\"";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "dG";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "G";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "15G";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "\"ad15G";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "d15G";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "dgg";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "gg";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "15gg";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "\"ad15gg";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "d15gg";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "gc20j";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "20gcj";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "gc%";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "J";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "25J";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const input = "u";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.Undo);
}

test "`C-r` = 'redo'" {
    const input = Key{ .key_code = 'r', .left_control = true };
    var state = State{ .Start = CommandBuilderData{} };
    const command = try vim.handleKey(direct_allocator, input, &state);
    if (command) |c| {
        testing.expect(std.meta.activeTag(c) == Command.Redo);
    } else {
        std.debug.panic("No command when expecting one.");
    }
}

test "`i` = 'enter insert mode' & state is modified to be in insert mode after" {
    const input = Key{ .key_code = 'i' };
    var state = State{ .Start = CommandBuilderData{} };
    const maybeCommand = try vim.handleKey(direct_allocator, input, &state);
    if (maybeCommand) |command| {
        testing.expect(std.meta.activeTag(state) == State.InInsertMode);
        testing.expect(std.meta.activeTag(command) == Command.EnterInsertMode);
    } else {
        std.debug.panic("No command when expecting one.");
    }
}

test "`iC-[` = 'enter insert mode, then exit it'" {
    const input = Key{ .key_code = 'i' };
    var state = State{ .Start = CommandBuilderData{} };
    const maybeCommand1 = try vim.handleKey(direct_allocator, input, &state);
    if (maybeCommand1) |command| {
        testing.expect(std.meta.activeTag(state) == State.InInsertMode);
        testing.expect(std.meta.activeTag(command) == Command.EnterInsertMode);
    } else {
        std.debug.panic("No command when expecting one.");
    }
    const maybeCommand2 = try vim.handleKey(direct_allocator, vim.ESCAPE_KEY, &state);
    if (maybeCommand2) |command| {
        testing.expect(std.meta.activeTag(state) == State.Start);
        testing.expect(std.meta.activeTag(command) == Command.ExitInsertMode);
    } else {
        std.debug.panic("No command when expecting one.");
    }
}

test "`igaf%C-[` = 'enter insert mode, then exit it'" {
    const input = "igaf%\x1b";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
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
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.ScrollTop);
}

test "`zz` = 'scroll view so that cursor is at center'" {
    const input = "zz";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.ScrollCenter);
}

test "`zb` = 'scroll view so that cursor is at bottom'" {
    const input = "zb";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
    testing.expectEqual(commands.count(), 1);
    const command_slice = commands.toSliceConst();
    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.ScrollBottom);
}

test "`qawibC-[q` = 'record macro into 'a'; insert 'b', escape'" {
    const input = "qawib\x1bq";
    const keys = stringToKeys(input.len, input);
    var state = State{ .Start = CommandBuilderData{} };
    const commands = try vim.handleKeys(direct_allocator, &keys, &state);
    testing.expectEqual(commands.count(), 6);
    const command_slice = commands.toSliceConst();

    const first_command = command_slice[0];
    testing.expect(std.meta.activeTag(first_command) == Command.BeginMacro);
    switch (first_command) {
        .BeginMacro => |slot| {
            testing.expectEqual(slot, 'a');
        },
        else => unreachable,
    }

    const second_command = command_slice[1];
    testing.expect(std.meta.activeTag(second_command) == Command.MotionOnly);
    switch (second_command) {
        .MotionOnly => |command_data| {
            switch (command_data.motion) {
                .UntilNextWord => |words| {
                    testing.expectEqual(words, 1);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }

    const third_command = command_slice[2];
    testing.expect(std.meta.activeTag(third_command) == Command.EnterInsertMode);

    const fourth_command = command_slice[3];
    testing.expect(std.meta.activeTag(fourth_command) == Command.Insert);
    switch (fourth_command) {
        .Insert => |character| {
            testing.expectEqual(character, 'b');
        },
        else => unreachable,
    }

    const fifth_command = command_slice[4];
    testing.expect(std.meta.activeTag(fifth_command) == Command.ExitInsertMode);

    const sixth_command = command_slice[5];
    testing.expect(std.meta.activeTag(sixth_command) == Command.EndMacro);
    switch (sixth_command) {
        .EndMacro => |end_macro_data| {
            testing.expectEqual(end_macro_data.commands.len, 4);

            testing.expect(std.meta.activeTag(end_macro_data.commands[0]) == Command.MotionOnly);
            switch (end_macro_data.commands[0]) {
                .MotionOnly => |command_data| {
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

            testing.expect(
                std.meta.activeTag(end_macro_data.commands[1]) == Command.EnterInsertMode,
            );

            testing.expect(std.meta.activeTag(end_macro_data.commands[2]) == Command.Insert);
            switch (end_macro_data.commands[2]) {
                .Insert => |character| {
                    testing.expectEqual(character, 'b');
                },
                else => unreachable,
            }

            testing.expect(std.meta.activeTag(end_macro_data.commands[3]) == Command.ExitInsertMode);
        },
        else => unreachable,
    }
}

pub fn runTests() void {}
