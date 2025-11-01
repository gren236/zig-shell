const std = @import("std");

const BuiltIn = enum {
    undefined,
    exit,
    echo,
    type,
};

pub fn handle_cmd_exit(status: u8) void {
    std.posix.exit(status);
}

pub fn handle_cmd_type(writer: *std.Io.Writer, arg: []const u8) !void {
    if (std.meta.stringToEnum(BuiltIn, arg) == null) {
        try writer.print("{s}: not found\n", .{arg});
        return;
    }

    try writer.print("{s} is a shell builtin\n", .{arg});
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
    const command = std.meta.stringToEnum(BuiltIn, cmd_iter.first()) orelse BuiltIn.undefined;

    defer stdout.flush() catch std.posix.exit(5);

    switch (command) {
        .exit => {
            const status: u8 = if (cmd_iter.next()) |arg| try std.fmt.parseUnsigned(u8, arg, 10) else 0;

            handle_cmd_exit(status);
        },
        .echo => try stdout.print("{s}\n", .{cmd_iter.rest()}),
        .type => try handle_cmd_type(stdout, cmd_iter.rest()),
        else => try stdout.print("{s}: command not found\n", .{user_input}),
    }
}

pub fn main() !void {
    while (true) {
        try handle();
    }
}
