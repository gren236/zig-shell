const std = @import("std");

pub const BuiltIn = enum {
    undefined,
    exit,
    echo,
    type,
    pwd,
    cd,
};

pub fn handleExit(args: Args) !void {
    const status: u8 = if (args.parsed.len != 0) try std.fmt.parseUnsigned(u8, args.parsed[0], 10) else 0;

    std.posix.exit(status);
}

pub fn handleType(allocator: std.mem.Allocator, writer: *std.Io.Writer, args: Args) !void {
    if (args.parsed.len == 0) return error.BadArguments;

    const arg = args.parsed[0];
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

pub fn handleCommand(allocator: std.mem.Allocator, writer: *std.Io.Writer, command: []const u8, args: Args) !void {
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
    try args_list.appendSlice(allocator, args.parsed);

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

pub fn handleEcho(writer: *std.Io.Writer, args: Args) !void {
    for (args.parsed, 0..) |arg, i| {
        if (i != 0) try writer.print(" ", .{});
        try writer.print("{s}", .{arg});
    }
    try writer.print("\n", .{});
}

pub fn handlePwd(allocator: std.mem.Allocator, writer: *std.Io.Writer) !void {
    const path = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(path);

    try writer.print("{s}\n", .{path});
}

pub fn handleCd(allocator: std.mem.Allocator, writer: *std.Io.Writer, args: Args) !void {
    var path: []u8 = undefined;
    defer allocator.free(path);

    var arg: []const u8 = undefined;
    if (args.parsed.len == 0) {
        arg = "~";
    } else {
        arg = args.parsed[0];
    }

    // check if ~ passed
    if (std.mem.startsWith(u8, arg, "~")) {
        const home_dir = try std.process.getEnvVarOwned(allocator, "HOME");
        defer allocator.free(home_dir);

        path = try std.fmt.allocPrint(allocator, "{s}{s}", .{ home_dir, arg[1..] });
    } else {
        path = try allocator.dupe(u8, arg);
    }

    std.posix.chdir(path) catch {
        try writer.print("cd: {s}: No such file or directory\n", .{arg});
    };
}

const Args = struct {
    parsed: []const []const u8,

    fn init(allocator: std.mem.Allocator, raw: []const u8) !Args {
        var parsed_list = try std.ArrayList([]const u8).initCapacity(allocator, 0);

        var in_single_quotes = false;
        var in_double_quotes = false;
        var arg_buf = try std.ArrayList(u8).initCapacity(allocator, raw.len);
        defer arg_buf.deinit(allocator); // just in case
        for (raw) |char| {
            // if ' met - toggle in single quotes, if not in double quotes already
            if (char == '\'' and !in_double_quotes) {
                in_single_quotes = if (in_single_quotes) false else true;
                continue;
            }

            // if " met - toggle in double quotes, if not in single quotes already
            if (char == '"' and !in_single_quotes) {
                in_double_quotes = if (in_double_quotes) false else true;
                continue;
            }

            if (char == ' ') {
                // if whitespace and we are in quotes - add it to the arg
                if (in_single_quotes or in_double_quotes) {
                    try arg_buf.append(allocator, char);
                    continue;
                }

                // if whitespace and not in quotes - finish this arg and reinit buffer
                if (arg_buf.items.len > 0) {
                    try parsed_list.append(allocator, try arg_buf.toOwnedSlice(allocator));
                    arg_buf = try std.ArrayList(u8).initCapacity(allocator, raw.len);
                    continue;
                }

                // not in quotes, arg has no chars - just skip
                continue;
            }

            // otherwise just add a regular char to arg
            try arg_buf.append(allocator, char);
        }

        // if no more chars and still in quotes - error
        if (in_single_quotes or in_double_quotes) {
            return error.BadArguments;
        }

        // check if there is a last arg not appended
        if (arg_buf.items.len > 0) {
            try parsed_list.append(allocator, try arg_buf.toOwnedSlice(allocator));
        }

        return .{
            .parsed = try parsed_list.toOwnedSlice(allocator),
        };
    }

    fn deinit(self: *Args, allocator: std.mem.Allocator) void {
        for (self.parsed) |arg| {
            allocator.free(arg);
        }

        allocator.free(self.parsed);
    }
};

test Args {
    const TestCase = struct {
        input: []const u8,
        expected: []const []const u8 = undefined,
        expectErr: bool = false,
    };
    const test_cases = [_]TestCase{
        .{
            .input = "hello world",
            .expected = &.{ "hello", "world" },
        },
        .{
            .input = "hello        world",
            .expected = &.{ "hello", "world" },
        },
        // test single quotes
        .{
            .input = "'hello' 'world'",
            .expected = &.{ "hello", "world" },
        },
        .{
            .input = "'hello\"' '\"world\"'",
            .expected = &.{ "hello\"", "\"world\"" },
        },
        .{
            .input = "'hello     world'",
            .expected = &.{"hello     world"},
        },
        .{
            .input = "hello''world",
            .expected = &.{"helloworld"},
        },
        // test double quotes
        .{
            .input = "\"hello\" \"world\"",
            .expected = &.{ "hello", "world" },
        },
        .{
            .input = "\"hello's\" \"wor'ld\"",
            .expected = &.{ "hello's", "wor'ld" },
        },
        .{
            .input = "\"hello      world\"",
            .expected = &.{"hello      world"},
        },
        .{
            .input = "hello\"\"world",
            .expected = &.{"helloworld"},
        },
        // test error
        .{
            .input = "hello'world",
            .expectErr = true,
        },
    };

    for (test_cases) |tc| {
        std.debug.print("Args testcase: {s}\n", .{tc.input});

        if (tc.expectErr) {
            try std.testing.expectError(error.BadArguments, Args.init(std.testing.allocator, tc.input));
        } else {
            var args = try Args.init(std.testing.allocator, tc.input);
            defer args.deinit(std.testing.allocator);
            try std.testing.expectEqualDeep(tc.expected, args.parsed);
        }
    }
}

pub fn handle(allocator: std.mem.Allocator, writer: *std.Io.Writer, args_iter: *std.mem.SplitIterator(u8, .scalar)) !void {
    const command_str = args_iter.first();
    const command = std.meta.stringToEnum(BuiltIn, command_str) orelse BuiltIn.undefined;

    defer writer.flush() catch std.posix.exit(5);

    var args = try Args.init(allocator, args_iter.rest());
    defer args.deinit(allocator);

    switch (command) {
        .exit => try handleExit(args),
        .echo => try handleEcho(writer, args),
        .type => try handleType(allocator, writer, args),
        .pwd => try handlePwd(allocator, writer),
        .cd => try handleCd(allocator, writer, args),
        else => try handleCommand(allocator, writer, command_str, args),
    }
}
