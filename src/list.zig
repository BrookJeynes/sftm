const std = @import("std");
const vaxis = @import("vaxis");
const Terminals = @import("terminals.zig");

pub fn List(comptime T: type, max: usize) type {
    return struct {
        const Self = @This();

        items: [max]T = undefined,
        len: usize = 0,
        selected: usize = 0,
        offset: usize = 0,

        pub fn append(self: *Self, item: T) !void {
            if (self.len + 1 == max) return error.Overflow;

            self.items[self.len] = item;
            self.len += 1;
        }

        pub fn clear(self: *Self) void {
            self.selected = 0;
            self.offset = 0;
            self.len = 0;
        }

        pub fn get(self: *Self, index: usize) !T {
            if (index >= self.len) {
                return error.OutOfBounds;
            }

            return self.items[index];
        }

        pub fn getAll(self: *Self) []T {
            return self.items[0..self.len];
        }

        /// Remove item and shift all elements down.
        pub fn remove(self: *Self, index: usize) !T {
            if (index >= self.len) {
                return error.OutOfBounds;
            }

            const ptr = self.items[self.selected];

            var i: usize = self.selected;
            while (i < self.len - 1) : (i += 1) {
                self.items[i] = self.items[i + 1];
            }
            self.len -= 1;

            if (self.selected > 0) {
                self.selected -= 1;
            }

            return ptr;
        }

        pub fn removeSelected(self: *Self) ?T {
            if (self.len == 0) return null;
            return self.remove(self.selected) catch unreachable;
        }

        pub fn getSelected(self: *Self) ?T {
            if (self.len == 0) return null;
            return self.get(self.selected) catch unreachable;
        }

        pub fn next(self: *Self, win_height: usize) void {
            if (self.selected + 1 < self.len) {
                self.selected += 1;

                if (self.items[self.offset..].len != win_height and self.selected >= self.offset + (win_height / 2)) {
                    self.offset += 1;
                }
            }
        }

        pub fn previous(self: *Self, win_height: usize) void {
            if (self.selected > 0) {
                self.selected -= 1;

                if (self.offset > 0 and self.selected < self.offset + (win_height / 2)) {
                    self.offset -= 1;
                }
            }
        }
    };
}
