const std = @import("std");

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

    try stdout.print("{s}: command not found\n", .{user_input});
    try stdout.flush();
}

pub fn main() !void {
    while (true) {
        try handle();
    }
}
