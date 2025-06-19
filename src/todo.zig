const std = @import("std");

pub const TodoStatus = enum {
    TODO,
    DONE,
    WAIT,
    NO,

    const StateNotFoundError = error{StateNotFoundError};

    /// Don't use this, this is just an example of the std.meta.stringToEnum
    pub fn fromName(str: []const u8) !TodoStatus {
        if (std.meta.stringToEnum(TodoStatus, str)) {
            return std.meta.stringToEnum(TodoStatus, str);
        } else {
            return error.StateNotFoundError;
        }
    }
};

pub const TodoItem = struct {
    message: []const u8,
    state: TodoStatus,
};

pub const TodoList = struct {
    items: std.ArrayList(TodoItem),
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn new(allocator: std.mem.Allocator) !Self {
        const list = std.ArrayList(TodoItem).init(allocator);
        return TodoList{ .items = list, .allocator = allocator };
    }

    pub fn append(self: *Self, item: TodoItem) !void {
        try self.items.append(item);
    }

    pub fn removeByIndex(self: *Self, idx: usize) void {
        _ = self.items.orderedRemove(idx);
    }

    pub fn printAll(self: *Self) !void {
        const writer = std.io.getStdOut().writer();

        for (self.items.items, 0..) |item, i| {
            try writer.print("{} [{s}] {s}\n", .{ i, @tagName(item.state), item.message });
        }
    }

    pub fn encode(self: *Self) !void {
        // posix only
        const home: ?[:0]const u8 = std.posix.getenvZ("HOME");

        if (home == null) {
            return error.HomeNotFound;
        }

        // Get ~/.cache file and create a todozig directory
        const cache_path = try std.fs.path.join(self.allocator, &[_][]const u8{ home.?, ".cache", "todozig" });
        defer self.allocator.free(cache_path);

        // create the directory and dont do anything if there is path already exists error
        _ = std.fs.makeDirAbsolute(cache_path) catch {};

        // Create the path for the json file and create it
        const file_path = try std.fs.path.join(self.allocator, &[_][]const u8{ cache_path, "data.json" });
        var file = try std.fs.createFileAbsolute(file_path, .{});
        defer file.close();

        const options = std.json.StringifyOptions{ .whitespace = .indent_2 };

        try std.json.stringify(self.items.items, options, file.writer());

        _ = try file.write("\n");
    }

    pub fn decode(self: *Self) !void {
        // Allocator, open file
        const file = std.fs.cwd().openFile("data.json", .{}) catch {
            return;
        };
        defer file.close();

        // Reads all the bytes from the current position to the end of the file.
        // On success, caller owns returned buffer.
        const content = try file.readToEndAlloc(self.allocator, 32000);

        const parsed = try std.json.parseFromSlice([]TodoItem, self.allocator, content, .{});
        defer parsed.deinit();

        // Put the parsed data into the ArrayList
        for (parsed.value) |e| {
            std.debug.print("{s} {any}", .{ e.message, e.state });
            try self.items.append(e);
        }
    }
};
