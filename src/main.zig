const std = @import("std");
const cmd = @import("cmd.zig");

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

    var gpa: std.heap.DebugAllocator(.{}) = .init;
    var arena_alloc = std.heap.ArenaAllocator.init(gpa.allocator());
    defer _ = arena_alloc.reset(.free_all);

    try cmd.handle(arena_alloc.allocator(), stdout, &cmd_iter);
}

pub fn main() !void {
    while (true) {
        try handle();
    }
}
