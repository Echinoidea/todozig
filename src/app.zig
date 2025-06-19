const std = @import("std");
const todo = @import("todo.zig");
const termsize = @import("termsize.zig");

const AppState = enum {
    DEFAULT,
    CREATE,
    DELETE,
    MODIFY_NAME,
    MODIFY_STATUS,
};

const AppInput = enum { CREATE, DELETE, RENAME, TOGGLE };

pub const App = struct {
    const Self = @This();

    current_state: AppState,
    todo_list: *todo.TodoList,
    allocator: std.mem.Allocator,

    pub fn getValidAction(self: *Self) !AppInput {
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

    pub fn getValidIndex(self: *Self) !usize {
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
        try self.todo_list.append(todo.TodoItem{ .message = title, .state = todo.TodoStatus.TODO });
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
