const std = @import("std");
const builtin = @import("builtin");
const Neocities = @import("Neocities");

pub const std_options: std.Options = .{
    .log_level = if (builtin.mode == .Debug) .debug else .info,
    .logFn = coloredLog,
};

const version = "0.1.2";

const usage =
    \\Usage: {s} [command] [options]
    \\
    \\Commands:
    // \\  push       | Upload a directory to your Neocities website
    // \\  pull       | Download all files from your Neocities website
    \\  upload     | Upload files to your Neocities website
    \\  delete     | Delete files from your Neocities website
    \\  info       | Display information about a Neocities website
    \\  list       | List files from your Neocities website
    \\  key        | Display the API key
    \\  logout     | Remove the API key from the configuration file
    \\  help       | Display information about a command
    \\  version    | Display program version
    \\
;

const usage_upload =
    \\Usage: {s} upload [sources] [destination]
    \\
    \\Description: Upload files to your Neocities website. Sources can only be files.
    \\             If no destination is specified, the default is the root directory.
    \\             If the destination is a directory, the sources will be uploaded to
    \\             that directory. If the destination is a file, the unique source
    \\             will be uploaded to that file. If there are multiple sources, the
    \\             last argument is the destination.
    \\
;

const usage_delete =
    \\Usage: {s} delete [files]
    \\
    \\Description: Delete files or directories on your Neocities website.
    \\             Be careful, this action cannot be undone.
    \\
;

const usage_info =
    \\Usage: {s} info [website]
    \\
    \\Description: Display information about a Neocities website. If no site is
    \\             specified, information about your saved website is displayed.
    \\
;

const usage_list =
    \\Usage: {s} list [-l] [directory]
    \\
    \\Description: Display a list of all files on your website.
    \\             If no directory is specified, all files will be listed.
    \\
    \\Flags:
    \\  --raw    Display the list without any formatting
    \\  --dir    Display only directories
    \\
;

const Config = struct {
    api_key: []const u8,
    username: []const u8,
};

const Color = enum(u8) {
    black = 30,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    default,
    bright_black = 90,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,

    const csi = "\x1b[";
    const reset = csi ++ "0m";
    const bold = csi ++ "1m";

    fn toSeq(comptime fg: Color) []const u8 {
        return comptime csi ++ std.fmt.digits2(@intFromEnum(fg)) ++ "m";
    }
};

var progname: []const u8 = undefined;

fn coloredLog(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime switch (message_level) {
        .err => Color.bold ++ Color.red.toSeq() ++ "error" ++ Color.reset,
        .warn => Color.bold ++ Color.yellow.toSeq() ++ "warning" ++ Color.reset,
        .info => Color.bold ++ Color.blue.toSeq() ++ "info" ++ Color.reset,
        .debug => Color.bold ++ Color.cyan.toSeq() ++ "debug" ++ Color.reset,
    };
    const scope_prefix = (if (scope != .default) "@" ++ @tagName(scope) else "") ++ ": ";
    const stderr = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stderr);
    const writer = bw.writer();

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    nosuspend {
        writer.print(level_txt ++ scope_prefix ++ format ++ "\n", args) catch return;
        bw.flush() catch return;
    }
}

// TODO: windows
fn getConfigPath(allocator: std.mem.Allocator) ![]const u8 {
    if (std.process.getEnvVarOwned(allocator, "XDG_CONFIG_HOME")) |xdg_config| {
        defer allocator.free(xdg_config);
        return try std.fmt.allocPrint(allocator, "{s}/neocities/config.json", .{xdg_config});
    } else |_| if (std.process.getEnvVarOwned(allocator, "HOME")) |home| {
        defer allocator.free(home);
        return try std.fmt.allocPrint(allocator, "{s}/.config/neocities/config.json", .{home});
    } else |err| {
        return err;
    }
}

fn getApiKey(allocator: std.mem.Allocator) ![]const u8 {
    if (std.process.getEnvVarOwned(allocator, "NEOCITIES_API_KEY")) |api_key| {
        return api_key;
    } else |err| {
        if (err != error.EnvironmentVariableNotFound) {
            return err;
        }
    }

    const config_path = try getConfigPath(allocator);
    defer allocator.free(config_path);
    const cwd = std.fs.cwd();
    const config_file = if (cwd.openFile(config_path, .{})) |config_file| blk: {
        const content = try config_file.readToEndAlloc(allocator, 4096);
        defer allocator.free(content);
        if (std.json.parseFromSlice(Config, allocator, content, .{})) |config| {
            defer config.deinit();
            return allocator.dupe(u8, config.value.api_key);
        } else |err| {
            std.log.warn("Failed to parse the configuration file: {}", .{err});
            break :blk try cwd.createFile(config_path, .{});
        }
    } else |err| blk: {
        if (err != error.FileNotFound) {
            return err;
        }
        try cwd.makePath(config_path[0 .. config_path.len - "config.json".len]);
        break :blk try cwd.createFile(config_path, .{});
    };

    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
    try stdout.writeAll("Please login to get your API key.\n");
    try stdout.writeAll("Username: ");
    const username = if (std.process.getEnvVarOwned(allocator, "NEOCITIES_USERNAME")) |name| blk: {
        try stdout.print("{s}\n", .{name});
        break :blk name;
    } else |_| blk: {
        break :blk (try stdin.readUntilDelimiterOrEofAlloc(allocator, '\n', 64)).?;
    };
    defer allocator.free(username);

    try stdout.writeAll("Password: ");

    const handle = std.os.linux.STDIN_FILENO;
    var original: std.os.linux.termios = undefined;
    _ = std.os.linux.tcgetattr(handle, &original);
    var hidden: std.os.linux.termios = original;
    hidden.lflag.ICANON = false;
    hidden.lflag.ECHO = false;
    _ = std.os.linux.tcsetattr(handle, .NOW, &hidden);
    errdefer _ = std.os.linux.tcsetattr(handle, .NOW, &original);

    const password = if (std.process.getEnvVarOwned(allocator, "NEOCITIES_PASSWORD")) |pass| blk: {
        break :blk pass;
    } else |_| blk: {
        var buf: [64]u8 = undefined;
        var size: usize = 0;
        while (true) {
            if (size == buf.len) {
                return error.StreamTooLong;
            }
            buf[size] = try stdin.readByte();
            switch (buf[size]) {
                '\n' => break,
                '\x7f' => {
                    if (size > 0) {
                        size -= 1;
                        try stdout.writeAll("\x08 \x08");
                    }
                    continue;
                },
                else => {},
            }
            size += 1;
            try stdout.writeAll("*");
        }
        try stdout.writeAll("\n");
        break :blk try allocator.dupe(u8, buf[0..size]);
    };
    defer allocator.free(password);

    _ = std.os.linux.tcsetattr(handle, .NOW, &original);

    const nc = Neocities.initPassword(allocator, username, password);
    const api_key_request = try nc.key();
    defer api_key_request.deinit();

    if (api_key_request.value.result != .success) {
        std.log.err("{s} ({s})", .{
            api_key_request.value.message.?,
            api_key_request.value.error_type.?,
        });
        std.process.exit(1);
    }

    const config: Config = .{
        .api_key = api_key_request.value.api_key.?,
        .username = username,
    };

    var ws = std.json.writeStream(config_file.writer(), .{});
    defer ws.deinit();
    try ws.write(config);

    std.log.info("Your API key has been saved to '{s}'.", .{config_path});

    return allocator.dupe(u8, api_key_request.value.api_key.?);
}

fn upload(args: *std.process.ArgIterator, nc: Neocities) !void {
    var filenames = std.ArrayList([]const u8).init(nc.allocator);
    defer filenames.deinit();
    while (args.next()) |arg| {
        try filenames.append(arg);
    }

    var dest: []const u8 = undefined;
    if (filenames.items.len == 0) {
        std.log.warn("No file specified to upload.", .{});
        return;
    } else if (filenames.items.len == 1) {
        std.log.warn("No destination specified, defaulting to '/'.", .{});
        dest = "";
    } else {
        dest = filenames.pop();
        if (dest[0] == '/') {
            dest = dest[1..];
        }
        if (dest.len > 1 and dest[dest.len - 1] == '/') {
            dest = dest[0 .. dest.len - 1];
        }
    }

    var dest_is_root = false;
    var dest_is_dir = false;
    if (std.mem.eql(u8, dest, "")) {
        dest_is_root = true;
        dest_is_dir = true;
    } else {
        const list_request = try nc.list(null);
        defer list_request.deinit();

        if (list_request.value.result != .success) {
            std.log.err("{s} ({s})", .{
                list_request.value.message.?,
                list_request.value.error_type.?,
            });
            std.process.exit(1);
        }

        const server_files = list_request.value.files.?;
        for (server_files) |file| {
            if (std.mem.eql(u8, file.path, dest)) {
                if (file.is_directory) {
                    dest_is_dir = true;
                }
                break;
            }
        }
    }

    if (filenames.items.len > 1 and !dest_is_dir) {
        std.log.warn("Multiple sources can only be uploaded to a directory.", .{});
        return;
    }

    if (!dest_is_root) {
        dest = try std.fmt.allocPrint(nc.allocator, "/{s}", .{dest});
    }
    defer if (!dest_is_root) nc.allocator.free(dest);

    for (filenames.items) |filename| {
        const dest_name = if (dest_is_dir) blk: {
            var iter = std.mem.splitBackwardsScalar(u8, filename, '/');
            const basename = iter.first();
            break :blk try std.fmt.allocPrint(nc.allocator, "{s}/{s}", .{ dest, basename });
        } else dest;
        defer if (dest_is_dir) nc.allocator.free(dest_name);

        std.log.info("Uploading {s} to {s} ...", .{ filename, dest_name });
        const file: Neocities.UploadFile = .{
            .dest_name = dest_name,
            .source_path = filename,
        };

        const upload_request = try nc.upload(&[_]Neocities.UploadFile{file});
        defer upload_request.deinit();

        if (upload_request.value.result != .success) {
            std.log.err("{s} ({s})", .{
                upload_request.value.message,
                upload_request.value.error_type.?,
            });
        } else {
            std.log.info(
                Color.green.toSeq() ++ "success" ++ Color.reset ++ ": {s}",
                .{upload_request.value.message},
            );
        }
    }
}

fn delete(args: *std.process.ArgIterator, nc: Neocities) !void {
    while (args.next()) |arg| {
        std.log.info("Deleting {s} ...", .{arg});
        const delete_request = try nc.delete(&[_][]const u8{arg});
        defer delete_request.deinit();

        if (delete_request.value.result != .success) {
            std.log.err("{s} ({s})", .{
                delete_request.value.message,
                delete_request.value.error_type.?,
            });
        } else {
            std.log.info(
                Color.green.toSeq() ++ "success" ++ Color.reset ++ ": {s}",
                .{delete_request.value.message},
            );
        }
    }
}

fn formatUnsigned(dest: []u8, number: usize) []u8 {
    var buf: [@sizeOf(@TypeOf(number)) * 4]u8 = undefined;
    std.debug.assert(buf.len <= dest.len);

    var i = buf.len;
    var n = number;
    var size_n: usize = 1;
    while (true) {
        i -= 1;
        buf[i] = @as(u8, @intCast(n % 10)) + '0';
        n /= 10;
        if (n == 0) {
            break;
        }
        if (size_n % 3 == 0) {
            i -= 1;
            buf[i] = ',';
        }
        size_n += 1;
    }

    return std.fmt.bufPrint(dest, "{s}", .{buf[i..]}) catch unreachable;
}

fn info(sitename: ?[]const u8, nc: Neocities) !void {
    const info_request = try nc.info(sitename);
    defer info_request.deinit();

    if (info_request.value.result != .success) {
        std.log.err("{s} ({s})", .{
            info_request.value.message.?,
            info_request.value.error_type.?,
        });
        std.process.exit(1);
    }

    const value = info_request.value.info.?;
    var buf: [64]u8 = undefined;
    const stdout = std.io.getStdOut().writer();

    try stdout.print(Color.bold ++ "sitename" ++ Color.reset ++ ":     {s}\n" ++
        Color.bold ++ "views" ++ Color.reset ++ ":        {s}\n" ++
        Color.bold ++ "hits" ++ Color.reset ++ ":         {s}\n" ++
        Color.bold ++ "created_at" ++ Color.reset ++ ":   {s}\n" ++
        Color.bold ++ "last_updated" ++ Color.reset ++ ": {s}\n", .{
        value.sitename,
        formatUnsigned(buf[0..], value.views),
        formatUnsigned(buf[32..], value.hits),
        trimDate(value.created_at),
        trimDate(value.last_updated),
    });
    if (value.domain) |domain| {
        try stdout.print(Color.bold ++ "domain" ++ Color.reset ++ ":       {s}\n", .{domain});
    }
    if (value.tags.len > 0) {
        try stdout.writeAll(Color.bold ++ "tags" ++ Color.reset ++ ":         [");
        for (value.tags, 0..) |tag, i| {
            if (i != 0) {
                try stdout.writeAll(", ");
            }
            try stdout.print("\"{s}\"", .{tag});
        }
        try stdout.writeAll("]\n");
    }
}

fn toHumanReadableSize(buf: []u8, size: usize) ![]u8 {
    const units = [_][]const u8{ "B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB" };
    var i: usize = 0;
    var s: f64 = @floatFromInt(size);
    while (s >= 1024.0 and i < units.len) {
        s /= 1024.0;
        i += 1;
    }
    return if (i == 0)
        std.fmt.bufPrint(buf, "{d:.0}{s}", .{ s, units[i] })
    else
        std.fmt.bufPrint(buf, "{d:.2}{s}", .{ s, units[i] });
}

// remove day and timezone
fn trimDate(date: []const u8) []const u8 {
    return date[5 .. date.len - 6];
}

fn list(args: *std.process.ArgIterator, nc: Neocities) !void {
    var is_raw = false;
    var only_dir = false;
    var path: ?[]const u8 = null;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--raw")) {
            is_raw = true;
        } else if (std.mem.eql(u8, arg, "--dir")){
            only_dir = true;
        } else {
            path = arg;
        }
    }

    const list_request = try nc.list(path);
    defer list_request.deinit();

    if (list_request.value.result != .success) {
        std.log.err("{s} ({s})", .{
            list_request.value.message.?,
            list_request.value.error_type.?,
        });
        std.process.exit(1);
    }

    const files = list_request.value.files.?;
    if (files.len == 0) {
        std.log.info("'{s}' is a file or is empty or doesn't exist.", .{path.?});
        return;
    }

    const stdout = std.io.getStdOut().writer();

    if (is_raw) {
        if (only_dir) {
            for (files) |file| {
                if (file.is_directory) {
                    try stdout.print("{s}\n", .{file.path});
                }
            }
        } else {
            for (files) |file| {
                try stdout.print("{s}\n", .{file.path});
            }
        }
        return;
    }

    var path_padding: usize = 0;
    var size_padding: usize = 0;
    var buf: [32]u8 = undefined;
    for (files) |file| {
        if (file.path.len > path_padding) {
            path_padding = file.path.len;
        }
        if (!file.is_directory) {
            const human_readable_size = try toHumanReadableSize(&buf, file.size.?);
            if (human_readable_size.len > size_padding) {
                size_padding = human_readable_size.len;
            }
        }
    }

    try stdout.writeAll(Color.bold);
    try stdout.writeAll("Path");
    try stdout.writeByteNTimes(' ', path_padding - 2);
    try stdout.writeAll("Size");
    try stdout.writeByteNTimes(' ', size_padding - 2);
    try stdout.writeAll("Date Modified\n");
    for (files) |file| {
        if (file.is_directory) {
            try stdout.print(Color.blue.toSeq() ++ "{s}", .{file.path});
            try stdout.writeByteNTimes(' ', path_padding - file.path.len + 4 + size_padding);
            try stdout.print(Color.reset ++ "{s}\n", .{trimDate(file.updated_at)});
        } else if (!only_dir) {
            try stdout.print(Color.green.toSeq() ++ "{s}", .{file.path});
            try stdout.writeByteNTimes(' ', path_padding - file.path.len + 2);
            const human_readable_size = try toHumanReadableSize(&buf, file.size.?);
            try stdout.print(Color.reset ++ "{s}", .{human_readable_size});
            try stdout.writeByteNTimes(' ', size_padding - human_readable_size.len + 2);
            try stdout.print("{s}\n", .{trimDate(file.updated_at)});
        }
        try stdout.writeAll(Color.bold);
    }
    try stdout.writeAll(Color.reset);
}

fn logout(args: *std.process.ArgIterator, allocator: std.mem.Allocator) !void {
    if (args.next()) |arg| {
        std.log.warn("Unknown argument: '{s}'\n", .{arg});
        try help(null);
        return;
    }

    const config_path = try getConfigPath(allocator);
    defer allocator.free(config_path);
    std.fs.deleteFileAbsolute(config_path) catch |err| {
        if (err != error.FileNotFound) {
            return err;
        }
    };
    std.log.info("Your API key has been removed from '{s}'.", .{config_path});
}

fn help(command: ?[]const u8) !void {
    const stderr = std.io.getStdErr().writer();
    if (command) |com| {
        if (std.mem.eql(u8, com, "upload")) {
            try stderr.print(usage_upload, .{progname});
        } else if (std.mem.eql(u8, com, "delete")) {
            try stderr.print(usage_delete, .{progname});
        } else if (std.mem.eql(u8, com, "info")) {
            try stderr.print(usage_info, .{progname});
        } else if (std.mem.eql(u8, com, "list")) {
            try stderr.print(usage_list, .{progname});
        } else {
            try stderr.print(usage, .{progname});
        }
    } else {
        try stderr.print(usage, .{progname});
    }
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    progname = args.next().?;

    const api_key = try getApiKey(allocator);
    defer allocator.free(api_key);
    const nc = Neocities.initApiKey(allocator, api_key);

    const command = args.next() orelse "help";
    if (std.mem.eql(u8, command, "upload")) {
        try upload(&args, nc);
    } else if (std.mem.eql(u8, command, "delete")) {
        try delete(&args, nc);
    } else if (std.mem.eql(u8, command, "info")) {
        try info(args.next(), nc);
    } else if (std.mem.eql(u8, command, "list")) {
        try list(&args, nc);
    } else if (std.mem.eql(u8, command, "key")) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("{s}\n", .{api_key});
    } else if (std.mem.eql(u8, command, "logout")) {
        try logout(&args, allocator);
    } else if (std.mem.eql(u8, command, "version")) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("{s} v" ++ version ++ "\n", .{progname});
    } else {
        try help(args.next());
    }
}
