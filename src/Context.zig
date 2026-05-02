const std = @import("std");
const Neocities = @import("Neocities");

const Context = @This();

io: std.Io,
allocator: std.mem.Allocator,
arena: *std.heap.ArenaAllocator,
env_map: *std.process.Environ.Map,
args: std.process.Args.Iterator,
api: Neocities,
