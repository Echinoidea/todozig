const std = @import("std");
const libtodo = @import("todo.zig");
const libapp = @import("app.zig");
const termsize = @import("termsize.zig");

const TodoList = libtodo.TodoList;
const App = libapp.App;

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
                const idx = app.getValidIndex() catch {
                    continue;
                };
                app.delete(idx);
            },
            .MODIFY_NAME => {
                const idx = app.getValidIndex() catch {
                    continue;
                };
                const writer = std.io.getStdOut().writer();

                const reader = std.io.getStdIn().reader();

                try writer.writeAll("New Title: ");
                var title: []const u8 = "No Title";
                while (true) {
                    if (try reader.readUntilDelimiterOrEofAlloc(allocator, '\n', 1024)) |input| {
                        title = input;
                        break;
                    }
                }

                app.todo_list.items.items[idx].message = title;
            },
            .MODIFY_STATUS => {
                const idx = app.getValidIndex() catch {
                    continue;
                };
                app.toggle(idx);
            },
        }

        try list.encode();
    }
}
