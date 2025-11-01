const std = @import("std");

const Command = enum {
    undefined,
    exit,
    echo,
};

pub fn handle_cmd_exit(status: u8) void {
    std.posix.exit(status);
}

pub fn handle() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    var stdout = &stdout_writer.interface;

    try stdout.print("$ ", .{});
    // DO NOT FORGET TO FLUSH!!!
    try stdout.flush();

    var stdin_buffer: [1024]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
    var stdin = &stdin_reader.interface;
    const user_input = try stdin.takeDelimiterExclusive('\n');

    var cmd_iter = std.mem.splitScalar(u8, user_input, ' ');
    const command = std.meta.stringToEnum(Command, cmd_iter.first()) orelse Command.undefined;

    defer stdout.flush() catch std.posix.exit(5);

    switch (command) {
        .exit => {
            const status: u8 = if (cmd_iter.next()) |arg| try std.fmt.parseUnsigned(u8, arg, 10) else 0;

            handle_cmd_exit(status);
        },
        .echo => {
            try stdout.print("{s}\n", .{cmd_iter.rest()});
        },
        else => try stdout.print("{s}: command not found\n", .{user_input}),
    }
}

pub fn main() !void {
    while (true) {
        try handle();
    }
}
