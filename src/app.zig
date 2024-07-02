const std = @import("std");
const vaxis = @import("vaxis");
const List = @import("list.zig").List;
const Terminals = @import("terminals.zig");
const Terminal = vaxis.widgets.Terminal;
const fuzzig = @import("fuzzig");

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

pub const State = enum { normal, input };

const Self = @This();

alloc: std.mem.Allocator,
vx: vaxis.Vaxis,
tty: vaxis.Tty,
env: std.process.EnvMap,
terminals: Terminals = undefined,
state: State = .normal,

last_known_height: usize = 0,

show_terminal_switcher: bool = false,
terminal_switcher_list: List(*Terminal, Terminals.max_terminals),

text_input: vaxis.widgets.TextInput,
text_input_buf: [std.fs.max_path_bytes]u8 = undefined,
searcher: fuzzig.Ascii,

pub fn init(alloc: std.mem.Allocator) !Self {
    var vx = try vaxis.init(alloc, .{
        .kitty_keyboard_flags = .{
            .report_text = false,
            .disambiguate = false,
            .report_events = false,
            .report_alternate_keys = false,
            .report_all_as_ctl_seqs = false,
        },
    });

    return Self{
        .alloc = alloc,
        .vx = vx,
        .tty = try vaxis.Tty.init(),
        .env = try std.process.getEnvMap(alloc),
        .terminals = Terminals.init(alloc),
        .terminal_switcher_list = List(*Terminal, Terminals.max_terminals){},
        .last_known_height = vx.window().height,
        .text_input = vaxis.widgets.TextInput.init(alloc, &vx.unicode),
        .searcher = try fuzzig.Ascii.init(
            alloc,
            std.fs.max_path_bytes,
            std.fs.max_path_bytes,
            .{ .case_sensitive = false },
        ),
    };
}

pub fn deinit(self: *Self) void {
    self.vx.deinit(self.alloc, self.tty.anyWriter());
    self.tty.deinit();
    self.env.deinit();
    self.terminals.deinit();
    self.text_input.deinit();
    self.searcher.deinit();
}

pub fn draw(self: *Self) !void {
    const win = self.vx.window();
    win.hideCursor();
    win.clear();

    try self.drawTerminal(win);

    if (self.show_terminal_switcher) {
        try self.drawTerminalSwitcher(win);
    }
}

pub fn drawTerminalSwitcher(self: *Self, win: vaxis.Window) !void {
    const pane_menu = win.child(.{
        .x_off = win.width / 4,
        .y_off = win.height / 4,
        .width = .{ .limit = win.width / 2 },
        .height = .{ .limit = win.height / 2 },
        .border = .{ .glyphs = .single_square, .where = .all },
    });
    self.last_known_height = pane_menu.height;

    pane_menu.fill(vaxis.Cell{ .style = .{ .bg = .{ .rgb = .{ 25, 25, 25 } } } });

    self.text_input.draw(pane_menu);

    for (self.terminal_switcher_list.getAll()[self.terminal_switcher_list.offset..], 0..) |term, i| {
        const cwd = try Terminals.getName(self.alloc, term.*);

        const selected = self.terminal_switcher_list.selected - self.terminal_switcher_list.offset;
        const is_selected = selected == i;

        if (i > pane_menu.height) {
            continue;
        }

        var w = pane_menu.child(.{
            .y_off = i + 1,
            .height = .{ .limit = 1 },
        });

        w.fill(vaxis.Cell{
            .style = if (is_selected) .{ .bg = .{ .rgb = .{ 45, 45, 45 } } } else .{ .bg = .{ .rgb = .{ 25, 25, 25 } } },
        });

        _ = try w.print(&.{.{
            .text = cwd,
            .style = if (is_selected) .{ .bg = .{ .rgb = .{ 45, 45, 45 } } } else .{ .bg = .{ .rgb = .{ 25, 25, 25 } } },
        }}, .{});
    }
}

pub fn drawTerminal(self: *Self, win: vaxis.Window) !void {
    if (self.terminals.getCurrentTerm()) |term| {
        const child = win.child(.{
            .width = .{ .limit = win.width },
            .height = .{ .limit = win.width },
        });

        try term.resize(.{
            .rows = child.height,
            .cols = child.width,
            .x_pixel = 0,
            .y_pixel = 0,
        });
        try term.draw(child);
    }
}

pub fn eventLoop(self: *Self) !void {
    var loop: vaxis.Loop(Event) = .{ .tty = &self.tty, .vaxis = &self.vx };
    try loop.init();

    try loop.start();
    defer loop.stop();

    var buffered = self.tty.bufferedWriter();

    var command: bool = false;
    var redraw: bool = false;
    while (true) {
        std.time.sleep(8 * std.time.ns_per_ms);

        if (self.terminals.terminals.getSelected()) |ptr| {
            var term = ptr;
            while (term.tryEvent()) |event| {
                redraw = true;
                switch (event) {
                    .bell => {},
                    .title_change => {},
                    .exited => {
                        if (self.terminals.terminals.len - 1 == 0) {
                            return;
                        }
                        self.terminals.removeSelected();
                        term = self.terminals.terminals.getSelected() orelse break;
                    },
                    .redraw => {},
                    .pwd_change => {},
                }
            }
        }

        while (loop.tryEvent()) |event| {
            redraw = true;

            switch (self.state) {
                .normal => {
                    switch (event) {
                        .key_press => |key| {
                            if (key.matches('c', .{ .ctrl = true })) return;

                            if (command) {
                                switch (key.codepoint) {
                                    'q' => {
                                        return;
                                    },
                                    'c' => {
                                        const cwd = try self.alloc.dupe(
                                            u8,
                                            if (self.terminals.terminals.getSelected().?.working_directory.items.len > 0)
                                                self.terminals.terminals.getSelected().?.working_directory.items
                                            else if (self.terminals.terminals.getSelected().?.cmd.working_directory) |init_dir|
                                                init_dir
                                            else
                                                try std.fs.cwd().realpathAlloc(self.alloc, "."),
                                        );

                                        const shell = self.env.get("SHELL") orelse "bash";
                                        const argv = [_][]const u8{shell};
                                        try self.terminals.create(
                                            &self.vx,
                                            &self.env,
                                            &argv,
                                            .{
                                                .winsize = .{
                                                    .rows = 24,
                                                    .cols = 100,
                                                    .x_pixel = 0,
                                                    .y_pixel = 0,
                                                },
                                                .scrollback_size = 0,
                                                .initial_working_directory = cwd,
                                            },
                                        );
                                    },
                                    'x' => {
                                        if (self.terminals.terminals.len - 1 == 0) {
                                            return;
                                        }
                                        self.terminals.removeSelected();
                                    },
                                    ']' => self.terminals.terminals.next(0),
                                    '[' => self.terminals.terminals.previous(0),
                                    ';' => {
                                        self.show_terminal_switcher = true;
                                        self.state = .input;

                                        self.terminal_switcher_list.clear();
                                        self.terminal_switcher_list.items = self.terminals.terminals.items;
                                        self.terminal_switcher_list.len = self.terminals.terminals.len;
                                    },
                                    else => {},
                                }

                                command = false;
                            } else if (self.terminals.getCurrentTerm()) |term| {
                                if (!self.show_terminal_switcher) {
                                    try term.update(.{ .key_press = key });
                                }
                            }

                            if (key.matches('a', .{ .ctrl = true })) command = true;
                        },
                        .winsize => |ws| {
                            try self.vx.resize(self.alloc, self.tty.anyWriter(), ws);
                        },
                    }
                },
                .input => {
                    switch (event) {
                        .key_press => |key| {
                            if (key.matches('c', .{ .ctrl = true })) return;

                            switch (key.codepoint) {
                                vaxis.Key.escape => {
                                    self.show_terminal_switcher = false;
                                    self.state = .normal;
                                    self.text_input.clearAndFree();
                                },
                                vaxis.Key.down => {
                                    self.terminal_switcher_list.next(self.last_known_height);
                                },
                                vaxis.Key.up => {
                                    self.terminal_switcher_list.previous(self.last_known_height);
                                },
                                vaxis.Key.enter => {
                                    self.text_input.clearAndFree();
                                    self.show_terminal_switcher = false;
                                    self.state = .normal;
                                    self.terminals.terminals.selected = self.terminal_switcher_list.selected;
                                },
                                else => {
                                    try self.text_input.update(.{ .key_press = key });
                                    self.terminal_switcher_list.selected = 0;

                                    var items: @TypeOf(self.terminal_switcher_list.items) = undefined;
                                    var len: usize = 0;

                                    // Fuzzy list.
                                    for (self.terminals.terminals.getAll()) |term| {
                                        const cwd = try Terminals.getName(self.alloc, term.*);
                                        self.text_input.cursor_idx = self.text_input.grapheme_count;
                                        const fuzzy_search = self.text_input.sliceToCursor(&self.text_input_buf);
                                        const score = self.searcher.score(cwd, fuzzy_search) orelse 0;
                                        if (fuzzy_search.len > 0 and score < 1) {
                                            continue;
                                        }

                                        items[len] = term;
                                        len += 1;
                                    }

                                    self.terminal_switcher_list.items = items;
                                    self.terminal_switcher_list.len = len;
                                },
                            }
                        },
                        .winsize => |ws| {
                            try self.vx.resize(self.alloc, self.tty.anyWriter(), ws);
                        },
                    }
                },
            }
        }

        if (!redraw) continue;
        redraw = false;

        try self.draw();

        try self.vx.render(buffered.writer().any());
        try buffered.flush();
    }
}
