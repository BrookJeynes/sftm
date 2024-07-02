const std = @import("std");
const vaxis = @import("vaxis");
const Terminal = vaxis.widgets.Terminal;
const List = @import("list.zig").List;

const Terminals = @This();

pub const max_terminals = 100;

alloc: std.mem.Allocator,
terminals: List(*Terminal, max_terminals),

pub fn init(alloc: std.mem.Allocator) Terminals {
    return Terminals{
        .alloc = alloc,
        .terminals = List(*Terminal, max_terminals){},
    };
}

pub fn deinit(self: *Terminals) void {
    while (self.terminals.len > 0) {
        _ = self.removeSelected();
    }

    if (Terminal.global_vts) |*global_vts| {
        global_vts.deinit();
    }
}

pub fn getCurrentTerm(self: *Terminals) ?*Terminal {
    return self.terminals.getSelected();
}

// TODO: Rename new window.
pub fn create(self: *Terminals, vx: *vaxis.Vaxis, env: *std.process.EnvMap, argv: []const []const u8, opts: Terminal.Options) !void {
    const ptr = try self.alloc.create(Terminal);
    ptr.* = try Terminal.init(
        self.alloc,
        argv,
        env,
        &vx.unicode,
        opts,
    );
    ptr.spawn() catch {
        if (ptr.cmd.working_directory) |init_cwd| {
            self.alloc.free(init_cwd);
        }
        ptr.deinit();
        self.alloc.destroy(ptr);

        return error.FailedToSpawn;
    };

    try self.terminals.append(ptr);
    self.terminals.selected = self.terminals.len - 1;
}

pub fn removeSelected(self: *Terminals) void {
    if (self.terminals.removeSelected()) |ptr| {
        if (ptr.cmd.working_directory) |init_cwd| {
            self.alloc.free(init_cwd);
        }
        ptr.deinit();
        self.alloc.destroy(ptr);
    }
}

pub fn getName(alloc: std.mem.Allocator, term: Terminal) ![]const u8 {
    return if (term.working_directory.items.len > 0)
        term.working_directory.items
    else if (term.cmd.working_directory) |init_dir|
        init_dir
    else
        try std.fs.cwd().realpathAlloc(alloc, ".");
}
