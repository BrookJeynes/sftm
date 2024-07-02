const std = @import("std");
const App = @import("app.zig");
const vaxis = @import("vaxis");

var app: App = undefined;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    app = try App.init(alloc);
    defer app.deinit();

    try app.vx.enterAltScreen(app.tty.anyWriter());
    defer app.vx.exitAltScreen(app.tty.anyWriter()) catch {};
    try app.vx.queryTerminal(app.tty.anyWriter(), 1 * std.time.ns_per_s);

    const shell = app.env.get("SHELL") orelse "bash";
    const argv = [_][]const u8{shell};
    try app.terminals.create(
        &app.vx,
        &app.env,
        &argv,
        .{
            .winsize = .{
                .rows = 24,
                .cols = 100,
                .x_pixel = 0,
                .y_pixel = 0,
            },
            .scrollback_size = 0,
            .initial_working_directory = try std.fs.cwd().realpathAlloc(app.alloc, "."),
        },
    );

    try app.eventLoop();
}

pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    app.vx.exitAltScreen(app.tty.anyWriter()) catch {};
    app.vx.deinit(app.alloc, app.tty.anyWriter());
    std.builtin.default_panic(msg, trace, ret_addr);
}
