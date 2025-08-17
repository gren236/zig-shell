const std = @import("std");

pub fn handle() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("$ ", .{});

    const stdin = std.io.getStdIn().reader();
    var buffer: [1024]u8 = undefined;
    const user_input = try stdin.readUntilDelimiter(&buffer, '\n');

    try stdout.print("{s}: command not found\n", .{user_input});
}

pub fn main() !void {
    while (true) {
        try handle();
    }
}
