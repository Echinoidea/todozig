const std = @import("std");
const termsize = @import("termsize.zig");

const TodoStatus = enum {
    TODO,
    DONE,
    WAIT,
    NO,

    const StateNotFoundError = error{StateNotFoundError};

    fn strEquals(a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }

    /// Don't use this, this is just an example of the std.meta.stringToEnum
    pub fn fromName(str: []const u8) !TodoStatus {
        if (std.meta.stringToEnum(TodoStatus, str)) {
            return std.meta.stringToEnum(TodoStatus, str);
        } else {
            return error.StateNotFoundError;
        }
    }
};

const TodoItem = struct {
    message: []const u8,
    state: TodoStatus,
};

const TodoList = struct {
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

/// 1. Show todo-list
/// 2. Await input
/// 3. Get input
///     a. Create new item (STATE)
///     b. Delete item (STATE)
///     c. Change item state (STATE)
///     d. Mark item as complete shortcut
/// 4. Do action and save
/// 5. Clear terminal
/// 6. Goto 1
const AppState = enum {
    DEFAULT,
    CREATE,
    DELETE,
    MODIFY_NAME,
    MODIFY_STATUS,
};

const AppInput = enum { CREATE, DELETE, RENAME, TOGGLE };

const App = struct {
    const Self = @This();

    current_state: AppState,
    todo_list: *TodoList,
    allocator: std.mem.Allocator,

    fn getValidAction(self: *Self) !AppInput {
        const reader = std.io.getStdIn().reader();

        while (true) {
            if (try reader.readUntilDelimiterOrEofAlloc(self.allocator, '\n', 512)) |input| {
                defer self.allocator.free(input);
                if (std.mem.eql(u8, input, "c")) {
                    return AppInput.CREATE;
                } else if (std.mem.eql(u8, input, "d")) {
                    return AppInput.DELETE;
                } else if (std.mem.eql(u8, input, "r")) {
                    return AppInput.RENAME;
                } else if (std.mem.eql(u8, input, "t")) {
                    return AppInput.TOGGLE;
                }
            }
        }
    }

    fn getValidIndex(self: *Self) !usize {
        const reader = std.io.getStdIn().reader();

        while (true) {
            if (try reader.readUntilDelimiterOrEofAlloc(self.allocator, '\n', 512)) |input| {
                defer self.allocator.free(input);
                const parsed = try std.fmt.parseInt(i64, input, 10);
                return @as(usize, @max(parsed, 0));
            }
        }
    }

    pub fn getInput(self: *Self) !void {
        self.current_state = switch (try getValidAction(self)) {
            AppInput.CREATE => AppState.CREATE,
            AppInput.DELETE => AppState.DELETE,
            AppInput.RENAME => AppState.MODIFY_NAME,
            AppInput.TOGGLE => AppState.MODIFY_STATUS,
        };
    }

    fn inputTodoTitle(self: *Self) ![]const u8 {
        const reader = std.io.getStdIn().reader();

        while (true) {
            if (try reader.readUntilDelimiterOrEofAlloc(self.allocator, '\n', 512)) |input| {
                defer self.allocator.free(input);

                return input;
            }
        }
    }

    fn clearTerminal() !void {
        const writer = std.io.getStdOut().writer();
        try writer.writeAll("\x1B[2J\x1B[H");
    }

    pub fn draw(self: *Self) !void {
        const writer = std.io.getStdOut().writer();
        try clearTerminal();

        try writer.writeAll("TODO:\n");
        try self.todo_list.printAll();

        const size: termsize.TermSize = try termsize.termSize(std.io.getStdOut()) orelse termsize.TermSize{ .height = 1, .width = 1 };

        // Print newlines until at bottom of terminal
        const title_space: usize = 1;
        const cmdlist_space: usize = 1;
        const cmdline_space: usize = 1;
        const nonwhitespace: usize = title_space + cmdlist_space + cmdline_space + self.todo_list.items.items.len;
        for (0..size.height - nonwhitespace) |_| {
            try writer.writeAll("\n");
        }
        try writer.writeAll("[c] create | [d] delete | [r] rename | [t] toggle : ");
    }

    pub fn create(self: *Self, title: []const u8) !void {
        try self.todo_list.append(TodoItem{ .message = title, .state = TodoStatus.TODO });
    }

    pub fn delete(self: *Self, idx: usize) void {
        if (idx >= self.todo_list.items.items.len) {
            return;
        }

        _ = self.todo_list.items.orderedRemove(idx);
    }

    pub fn toggle(self: *Self, idx: usize) void {
        if (idx >= self.todo_list.items.items.len) {
            return;
        }

        if (self.todo_list.items.items[idx].state == .TODO) {
            self.todo_list.items.items[idx].state = .DONE;
        } else {
            self.todo_list.items.items[idx].state = .TODO;
        }
    }

    pub fn printPrompt(self: *Self) !void {
        const writer = std.io.getStdOut().writer();

        const cmd_prompt = switch (self.current_state) {
            AppState.DEFAULT => "",
            AppState.CREATE => "Title: ",
            AppState.DELETE => "Index: ",
            AppState.MODIFY_NAME => "Index: ",
            AppState.MODIFY_STATUS => "Index: ",
        };

        try writer.writeAll(cmd_prompt);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var list = try TodoList.new(allocator);
    defer list.items.deinit();

    // // Read the todo-list
    try list.decode();
    std.debug.print("{}", .{list.items.items.len});

    var app: App = App{ .allocator = allocator, .current_state = .DEFAULT, .todo_list = &list };

    while (true) {
        try app.draw();
        _ = try app.getInput();
        try app.printPrompt();
        switch (app.current_state) {
            .DEFAULT => {},
            .CREATE => {
                const reader = std.io.getStdIn().reader();

                var title: []const u8 = "No Title";
                while (true) {
                    if (try reader.readUntilDelimiterOrEofAlloc(allocator, '\n', 512)) |input| {
                        title = input;
                        break;
                    }
                }
                try app.create(title);
            },
            .DELETE => {
                const idx = try app.getValidIndex();
                app.delete(idx);
            },
            .MODIFY_NAME => {
                const idx = try app.getValidIndex();
                const writer = std.io.getStdOut().writer();

                const reader = std.io.getStdIn().reader();

                try writer.writeAll("New Title: ");
                var title: []const u8 = "No Title";
                while (true) {
                    if (try reader.readUntilDelimiterOrEofAlloc(allocator, '\n', 512)) |input| {
                        title = input;
                        break;
                    }
                }

                app.todo_list.items.items[idx].message = title;
            },
            .MODIFY_STATUS => {
                const idx = try app.getValidIndex();
                app.toggle(idx);
            },
        }

        try list.encode();
    }
}
