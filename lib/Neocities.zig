const std = @import("std");
const Neocities = @This();
const parseFromSlice = std.json.parseFromSlice;

const protocol = "https";
const api_url = "neocities.org/api";
const boundary = "x------------xXx--------------x";

auth: union(enum) {
    api_key: []const u8,
    password: struct {
        user: []const u8,
        pass: []const u8,
    },
},
allocator: std.mem.Allocator,

pub const InfoRequest = struct {
    result: enum { success, @"error" },
    error_type: ?[]const u8 = null,
    message: ?[]const u8 = null,
    info: ?struct {
        sitename: []const u8,
        views: usize,
        hits: usize,
        created_at: []const u8,
        last_updated: []const u8,
        domain: ?[]const u8,
        tags: [][]const u8,
    } = null,
};

pub const ListRequest = struct {
    result: enum { success, @"error" },
    error_type: ?[]const u8 = null,
    message: ?[]const u8 = null,
    files: ?[]struct {
        path: []const u8,
        is_directory: bool,
        size: ?usize = null,
        created_at: []const u8,
        updated_at: []const u8,
        sha1_hash: ?[]const u8 = null,
    } = null,
};

pub const KeyRequest = struct {
    result: enum { success, @"error" },
    error_type: ?[]const u8 = null,
    message: ?[]const u8 = null,
    api_key: ?[]const u8 = null,
};

pub const DeleteRequest = struct {
    result: enum { success, @"error" },
    error_type: ?[]const u8 = null,
    message: []const u8,
};

pub const UploadRequest = struct {
    result: enum { success, @"error" },
    error_type: ?[]const u8 = null,
    message: []const u8,
};

pub const UploadFile = struct {
    dest_name: []const u8,
    source_path: []const u8,
};

const PostMethod = enum { delete, upload };

pub fn initApiKey(allocator: std.mem.Allocator, api_key: []const u8) Neocities {
    return Neocities{
        .auth = .{ .api_key = api_key },
        .allocator = allocator,
    };
}

pub fn initPassword(allocator: std.mem.Allocator, user: []const u8, pass: []const u8) Neocities {
    return Neocities{
        .auth = .{ .password = .{ .user = user, .pass = pass } },
        .allocator = allocator,
    };
}

pub fn info(self: Neocities, sitename: ?[]const u8) !std.json.Parsed(InfoRequest) {
    var body: []const u8 = undefined;
    if (sitename) |s| {
        const method = try std.fmt.allocPrint(self.allocator, "info?sitename={s}", .{s});
        defer self.allocator.free(method);
        body = try self.get(method, true);
    } else {
        body = try self.get("info", false);
    }
    defer self.allocator.free(body);

    std.log.debug("info(): body: \n{s}", .{body});

    return try parseFromSlice(InfoRequest, self.allocator, body, .{ .allocate = .alloc_always });
}

pub fn list(self: Neocities, path: ?[]const u8) !std.json.Parsed(ListRequest) {
    var body: []const u8 = undefined;
    if (path) |p| {
        const method = try std.fmt.allocPrint(self.allocator, "list?path={s}", .{p});
        defer self.allocator.free(method);
        body = try self.get(method, false);
    } else {
        body = try self.get("list", false);
    }
    defer self.allocator.free(body);

    std.log.debug("list(): body: \n{s}", .{body});

    return parseFromSlice(ListRequest, self.allocator, body, .{ .allocate = .alloc_always });
}

pub fn key(self: Neocities) !std.json.Parsed(KeyRequest) {
    const body = try self.get("key", false);
    defer self.allocator.free(body);

    std.log.debug("key(): body: \n{s}", .{body});

    return parseFromSlice(KeyRequest, self.allocator, body, .{ .allocate = .alloc_always });
}

pub fn delete(self: Neocities, filenames: []const []const u8) !std.json.Parsed(DeleteRequest) {
    if (filenames.len == 0) {
        return error.EmptySlice;
    }

    var payload_builder: std.ArrayListUnmanaged(u8) = .{};
    for (filenames) |filename| {
        try payload_builder.appendSlice(self.allocator, "filenames[]=");
        try payload_builder.appendSlice(self.allocator, filename);
        try payload_builder.append(self.allocator, '&');
    }
    _ = payload_builder.pop();
    const payload = try payload_builder.toOwnedSlice(self.allocator);
    defer self.allocator.free(payload);

    std.log.debug("delete(): payload: {s}", .{payload});

    const body = try self.post(.delete, payload);
    defer self.allocator.free(body);

    std.log.debug("delete(): body: \n{s}", .{body});

    return parseFromSlice(DeleteRequest, self.allocator, body, .{ .allocate = .alloc_always });
}

pub fn upload(self: Neocities, files: []const UploadFile) !std.json.Parsed(UploadRequest) {
    if (files.len == 0) {
        return error.EmptySlice;
    }

    const cwd = std.fs.cwd();
    var payload_builder = std.ArrayList(u8).init(self.allocator);
    try payload_builder.appendSlice("--" ++ boundary);
    for (files) |file| {
        try payload_builder.appendSlice("\r\nContent-Disposition: form-data; name=\"");
        try payload_builder.appendSlice(file.dest_name);
        try payload_builder.appendSlice("\"; filename=\"");
        try payload_builder.appendSlice(file.dest_name);
        // TODO: add content type
        // try payload_builder.appendSlice("\"\r\nContent-Type: application/octet-stream\r\n\r\n");
        try payload_builder.appendSlice("\"\r\n\r\n");
        const f = try cwd.openFile(file.source_path, .{});
        defer f.close();
        try f.reader().readAllArrayList(&payload_builder, 1024 * 1024 * 4);
        try payload_builder.appendSlice("\r\n--" ++ boundary);
    }
    try payload_builder.appendSlice("--\r\n");
    const payload = try payload_builder.toOwnedSlice();
    defer self.allocator.free(payload);

    std.log.debug("upload(): payload: {s}", .{payload});

    const body = try self.post(.upload, payload);
    defer self.allocator.free(body);

    std.log.debug("upload(): body: \n{s}", .{body});

    return parseFromSlice(UploadRequest, self.allocator, body, .{ .allocate = .alloc_always });
}

fn get(self: Neocities, method: []const u8, no_auth: bool) ![]const u8 {
    var client: std.http.Client = .{ .allocator = self.allocator };
    defer client.deinit();

    const url = if (self.auth == .api_key or no_auth)
        try std.fmt.allocPrint(
            self.allocator,
            protocol ++ "://" ++ api_url ++ "/{s}",
            .{method},
        )
    else
        try std.fmt.allocPrint(
            self.allocator,
            protocol ++ "://{s}:{s}@" ++ api_url ++ "/{s}",
            .{ self.auth.password.user, self.auth.password.pass, method },
        );
    defer self.allocator.free(url);
    const uri = try std.Uri.parse(url);

    const authorization = if (self.auth == .api_key and !no_auth)
        try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.auth.api_key})
    else
        null;
    defer if (authorization) |auth| self.allocator.free(auth);

    var header_buf: [4096]u8 = undefined;
    var req = try client.open(.GET, uri, .{
        .server_header_buffer = &header_buf,
        .headers = if (authorization) |a| .{ .authorization = .{ .override = a } } else .{},
    });
    defer req.deinit();
    try req.send();
    try req.finish();
    try req.wait();
    // try std.testing.expectEqual(req.response.status, .ok);

    return req.reader().readAllAlloc(self.allocator, 1024 * 1024 * 4);
}

fn post(self: Neocities, method: PostMethod, payload: []const u8) ![]const u8 {
    var client: std.http.Client = .{ .allocator = self.allocator };
    defer client.deinit();

    const url = if (self.auth == .api_key)
        try std.fmt.allocPrint(
            self.allocator,
            protocol ++ "://" ++ api_url ++ "/{s}",
            .{@tagName(method)},
        )
    else
        try std.fmt.allocPrint(
            self.allocator,
            protocol ++ "://{s}:{s}@" ++ api_url ++ "/{s}",
            .{ self.auth.password.user, self.auth.password.pass, @tagName(method) },
        );
    defer self.allocator.free(url);
    const uri = try std.Uri.parse(url);

    const authorization = if (self.auth == .api_key)
        try std.fmt.allocPrint(self.allocator, "Bearer {s}", .{self.auth.api_key})
    else
        null;
    defer if (authorization) |auth| self.allocator.free(auth);

    var header_buf: [4096]u8 = undefined;
    var req = try client.open(.POST, uri, .{
        .server_header_buffer = &header_buf,
        .headers = .{
            .authorization = if (authorization) |a| .{ .override = a } else .default,
            .content_type = if (method == .upload)
                .{ .override = "multipart/form-data; boundary=" ++ boundary }
            else
                .{ .override = "application/x-www-form-urlencoded" },
        },
    });
    defer req.deinit();
    req.transfer_encoding = .{ .content_length = payload.len };
    try req.send();
    try req.writeAll(payload);
    try req.finish();
    try req.wait();
    // try std.testing.expectEqual(req.response.status, .ok);

    return req.reader().readAllAlloc(self.allocator, 1024 * 1024 * 4);
}

test "fake user" {
    const nc = initPassword(std.testing.allocator, "user", "pass");

    const info_json = try nc.info(null);
    defer info_json.deinit();
    try std.testing.expect(info_json.value.result == .@"error");

    const info_sitename_json = try nc.info("ratakor");
    defer info_sitename_json.deinit();
    try std.testing.expect(info_sitename_json.value.result == .success);

    const list_json = try nc.list(null);
    defer list_json.deinit();
    try std.testing.expect(list_json.value.result == .@"error");

    const key_json = try nc.key();
    defer key_json.deinit();
    try std.testing.expect(key_json.value.result == .@"error");

    const upload_json = try nc.upload(&[_]UploadFile{.{
        .dest_name = "README.md",
        .source_path = "README.md",
    }});
    defer upload_json.deinit();
    try std.testing.expect(upload_json.value.result == .@"error");

    const delete_json = try nc.delete(&[_][]const u8{"README.md"});
    defer delete_json.deinit();
    try std.testing.expect(delete_json.value.result == .@"error");
}

// test "user with password" {
//     const name = std.c.getenv("NEOCITIES_USER") orelse unreachable;
//     const pass = std.c.getenv("NEOCITIES_PASS") orelse unreachable;
//     const nc = initPassword(
//         std.testing.allocator,
//         name[0..std.mem.len(name)],
//         pass[0..std.mem.len(pass)],
//     );

//     const info_json = try nc.info(null);
//     defer info_json.deinit();
//     try std.testing.expect(info_json.value.result == .success);

//     const list_json = try nc.list(null);
//     defer list_json.deinit();
//     try std.testing.expect(list_json.value.result == .success);

//     const key_json = try nc.key();
//     defer key_json.deinit();
//     try std.testing.expect(key_json.value.result == .success);

//     const upload_json = try nc.upload(&[_]UploadFile{.{
//         .dest_name = "README.md",
//         .source_path = "README.md",
//     }});
//     defer upload_json.deinit();
//     try std.testing.expect(upload_json.value.result == .success);

//     const delete_json = try nc.delete(&[_][]const u8{ "README.md" });
//     defer delete_json.deinit();
//     try std.testing.expect(delete_json.value.result == .success);

//     const delete_error_json = try nc.delete(&[_][]const u8{ "README.md" });
//     defer delete_error_json.deinit();
//     try std.testing.expect(delete_error_json.value.result == .@"error");
// }

// test "user with api key" {
//     const api_key = std.c.getenv("NEOCITIES_API_KEY") orelse unreachable;
//     const nc = initApiKey(std.testing.allocator, api_key[0..std.mem.len(api_key)]);

//     const info_json = try nc.info(null);
//     defer info_json.deinit();
//     try std.testing.expect(info_json.value.result == .success);

//     const list_json = try nc.list(null);
//     defer list_json.deinit();
//     try std.testing.expect(list_json.value.result == .success);

//     const key_json = try nc.key();
//     defer key_json.deinit();
//     try std.testing.expect(key_json.value.result == .success);

//     const upload_json = try nc.upload(&[_]UploadFile{.{
//         .dest_name = "README.md",
//         .source_path = "README.md",
//     }});
//     defer upload_json.deinit();
//     try std.testing.expect(upload_json.value.result == .success);

//     const delete_json = try nc.delete(&[_][]const u8{ "README.md" });
//     defer delete_json.deinit();
//     try std.testing.expect(delete_json.value.result == .success);

//     const delete_error_json = try nc.delete(&[_][]const u8{ "README.md" });
//     defer delete_error_json.deinit();
//     try std.testing.expect(delete_error_json.value.result == .@"error");
// }
