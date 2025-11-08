const std = @import("std");

pub const BuiltIn = enum {
    undefined,
    exit,
    echo,
    type,
    pwd,
    cd,
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

pub fn handleCommand(allocator: std.mem.Allocator, writer: *std.Io.Writer, command: []const u8, args_str: []const u8) !void {
    // check if command exists
    const path_val = try std.process.getEnvVarOwned(allocator, "PATH");
    defer allocator.free(path_val);

    _ = checkCommandInPath(allocator, path_val, command) catch {
        try writer.print("{s}: command not found\n", .{command});
        return;
    };

    // now run it if found
    var args_list = try std.ArrayList([]const u8).initCapacity(allocator, 1);
    defer args_list.deinit(allocator);

    try args_list.append(allocator, command);

    var args_iter = std.mem.splitScalar(u8, args_str, ' ');
    while (args_iter.next()) |arg| {
        try args_list.append(allocator, arg);
    }

    var cmd_proc = std.process.Child.init(args_list.items, allocator);
    _ = try cmd_proc.spawnAndWait();
}

fn checkCommandInPath(allocator: std.mem.Allocator, path_str: []const u8, command: []const u8) ![]const u8 {
    // first try if command already accessible (AKA absolute path)
    if (std.posix.access(command, std.posix.X_OK)) {
        return command;
    } else |_| {}

    // if not accessible, check in path var
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

pub fn handlePwd(allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
    const path = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(path);

    try writer.print("{s}\n", .{path});
}

pub fn handleCd(writer: *std.Io.Writer, arg: []const u8) !void {
    std.posix.chdir(arg) catch {
        try writer.print("cd: {s}: No such file or directory\n", .{arg});
    };
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
        .pwd => try handlePwd(allocator, writer),
        .cd => try handleCd(writer, args_iter.rest()),
        else => try handleCommand(allocator, writer, command_str, args_iter.rest()),
    }
}
