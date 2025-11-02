const std = @import("std");

pub const BuiltIn = enum {
    undefined,
    exit,
    echo,
    type,
};

pub fn handleExit(status: u8) void {
    std.posix.exit(status);
}

pub fn handleType(allocator: std.mem.Allocator, writer: *std.Io.Writer, arg: []const u8) !void {
    if (std.meta.stringToEnum(BuiltIn, arg) != null) {
        try writer.print("{s} is a shell builtin\n", .{arg});
        return;
    }

    const path_val = try std.process.getEnvVarOwned(allocator, "PATH");
    defer allocator.free(path_val);

    const full_path = checkCommandInPath(allocator, path_val, arg) catch {
        try writer.print("{s}: not found\n", .{arg});
        return;
    };
    defer allocator.free(full_path);

    try writer.print("{s} is {s}\n", .{ arg, full_path });
}

fn checkCommandInPath(allocator: std.mem.Allocator, path_str: []const u8, command: []const u8) ![]const u8 {
    var paths_iter = std.mem.splitScalar(u8, path_str, ':');

    while (paths_iter.next()) |path_dir| {
        const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ path_dir, command });

        std.posix.access(path, std.posix.X_OK) catch {
            allocator.free(path);
            continue;
        };

        return path;
    }

    return error.NotFound;
}

pub fn handleEcho(writer: *std.Io.Writer, arg: []const u8) !void {
    try writer.print("{s}\n", .{arg});
}

pub fn handle(allocator: std.mem.Allocator, writer: *std.Io.Writer, args_iter: *std.mem.SplitIterator(u8, .scalar)) !void {
    const command_str = args_iter.first();
    const command = std.meta.stringToEnum(BuiltIn, command_str) orelse BuiltIn.undefined;

    defer writer.flush() catch std.posix.exit(5);

    switch (command) {
        .exit => {
            const status: u8 = if (args_iter.next()) |arg| try std.fmt.parseUnsigned(u8, arg, 10) else 0;

            handleExit(status);
        },
        .echo => try handleEcho(writer, args_iter.rest()),
        .type => try handleType(allocator, writer, args_iter.rest()),
        else => try writer.print("{s}: command not found\n", .{command_str}),
    }
}
