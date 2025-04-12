const std = @import("std");
const Awacator = std.mem.Allocator;
const AnyReader = std.io.AnyReader;
const AnyWriter = std.io.AnyWriter;

const awascii = @import("awascii.zig");
const Awatizer = @import("Awatizer.zig");

awacator: Awacator,
labels: [32]?usize,
commands: []const Command,
pc: usize = 0,
abyss: std.ArrayListUnmanaged(Bubble),

pub const FromAwaStreamError = error{OutOfMemory} || Awatizer.NextError;

pub const NextError = error{
    AbyssUnderflow,
    Invalid,
    InvalidAwascii,
    JumpToUnlabbeled,
    MathError,
    OutOfMemory,
    Unexpected,
};

pub const Command = union(Awatizer.CommandType) {
    /// Must never be used. Removed automatically in `fromAwaStream`.
    nop: void,
    prn: void,
    pr1: void,
    red: void,
    r3d: void,
    blw: i8,
    sbm: u5,
    pop: void,
    dpl: void,
    srn: u5,
    mrg: void,
    add: void,
    sub: void,
    mul: void,
    div: void,
    cnt: void,
    /// Must never be used. Removed automatically in `fromAwaStream`.
    lbl: u5,
    jmp: u5,
    eql: void,
    lss: void,
    gr8: void,
    trm: void,
};

pub const Bubble = union(enum) {
    simple: i32,
    double: std.ArrayListUnmanaged(Bubble),

    pub fn deinit(self: *Bubble, awacator: Awacator) void {
        switch (self.*) {
            .simple => {},
            .double => |*bubbles| {
                for (bubbles.items) |*bubble| {
                    bubble.deinit(awacator);
                }
                bubbles.deinit(awacator);
            },
        }
        self.* = undefined;
    }

    pub fn dupe(self: Bubble, awacator: Awacator) Awacator.Error!Bubble {
        switch (self) {
            .simple => |value| return .{ .simple = value },
            .double => |bubbles| {
                var new_bubble: Bubble = .{ .double = try .initCapacity(awacator, bubbles.items.len) };
                errdefer new_bubble.deinit(awacator);

                for (bubbles.items) |bubble| {
                    new_bubble.double.appendAssumeCapacity(try bubble.dupe(awacator));
                }
                return new_bubble;
            },
        }
    }
};

pub fn fromAwaStream(awacator: Awacator, awatizer: *Awatizer) FromAwaStreamError!@This() {
    var labels: [32]?usize = @splat(null);
    var commands = std.ArrayList(Command).init(awacator);
    errdefer commands.deinit();

    while (try awatizer.next()) |awa| {
        switch (awa) {
            .command => |cmd| switch (cmd) {
                .nop => {},
                inline .prn,
                .pr1,
                .red,
                .r3d,
                .pop,
                .dpl,
                .mrg,
                .add,
                .sub,
                .mul,
                .div,
                .cnt,
                .eql,
                .lss,
                .gr8,
                .trm,
                => |tag| try commands.append(tag),
                inline .sbm, .srn, .jmp => |tag| {
                    const param = try awatizer.next() orelse return Awatizer.NextError.EndOfStream;
                    switch (param) {
                        .param_u5 => |i| try commands.append(@unionInit(Command, @tagName(tag), i)),
                        else => unreachable, // Awatizer has us covered
                    }
                },
                .blw => {
                    const param = try awatizer.next() orelse return Awatizer.NextError.EndOfStream;
                    switch (param) {
                        .param_i8 => |i| try commands.append(.{ .blw = i }),
                        else => unreachable, // Awatizer has us covered
                    }
                },
                .lbl => {
                    const label = try awatizer.next() orelse return Awatizer.NextError.EndOfStream;
                    switch (label) {
                        .param_u5 => |i| labels[i] = commands.items.len,
                        else => unreachable, // Awatizer has us covered
                    }
                },
            },
            .param_u5, .param_i8 => unreachable, // Awatizer has us covered
        }
    }

    return .{
        .awacator = awacator,
        .labels = labels,
        .commands = try commands.toOwnedSlice(),
        .abyss = .empty,
    };
}

pub fn deinit(self: *@This()) void {
    self.awacator.free(self.commands);
    self.abyss.deinit(self.awacator);
    self.* = undefined;
}

/// Run the next command. Returns `false` if the program has terminated, `true` otherwise.
///
/// All input is read from `in`, and all output is written to `out`.
pub fn next(self: *@This(), in: AnyReader, out: AnyWriter) NextError!bool {
    if (self.pc >= self.commands.len) return false;

    const cmd = self.commands[self.pc];
    switch (cmd) {
        .nop, .lbl => {}, // Labels are already set at initialization
        .prn => {
            var bubble = self.abyss.pop() orelse return NextError.AbyssUnderflow;
            defer bubble.deinit(self.awacator);
            try print(out, bubble);
        },
        .pr1 => {
            var bubble = self.abyss.pop() orelse return NextError.AbyssUnderflow;
            defer bubble.deinit(self.awacator);
            try printNum(out, bubble);
        },
        .red => {
            var bubble: Bubble = .{ .double = .{} };
            errdefer bubble.deinit(self.awacator);
            while (true) {
                const c = try readAwascii(in);
                if (c == awascii.IICSawA['\n'].?) break;
                try bubble.double.append(self.awacator, .{ .simple = c });
            }
            try self.abyss.append(self.awacator, bubble);
        },
        .r3d => early: {
            // Skip to first digit
            var value: i32 = while (true) {
                const c = awascii.IICSawA[in.readByte() catch return NextError.Unexpected] orelse continue;
                switch (c) {
                    awascii.IICSawA['\n'].? => {
                        try self.abyss.append(self.awacator, .{ .simple = 0 });
                        break :early;
                    },
                    // '0' to '9'
                    0x2a...0x33 => break c - 0x2a,
                    else => continue,
                }
            };

            while (true) {
                const c = awascii.IICSawA[in.readByte() catch return NextError.Unexpected] orelse continue;
                switch (c) {
                    // '0' to '9'
                    0x2a...0x33 => {
                        value *%= 10;
                        value +%= c - 0x2a;
                    },
                    else => break,
                }
            }

            try self.abyss.append(self.awacator, .{ .simple = value });
        },
        .blw => |value| {
            try self.abyss.append(self.awacator, .{ .simple = value });
        },
        .sbm => |amount| {
            const top = self.abyss.getLastOrNull() orelse return NextError.AbyssUnderflow;
            const amt = @min(
                if (amount == 0) std.math.maxInt(usize) else @as(usize, amount),
                self.abyss.items.len - 1,
            );
            std.mem.copyBackwards(
                Bubble,
                self.abyss.items[self.abyss.items.len - amt ..][0..amt],
                self.abyss.items[self.abyss.items.len - amt - 1 ..][0..amt],
            );
            self.abyss.items[self.abyss.items.len - amt - 1] = top;
        },
        .pop => {
            var popped = self.abyss.pop() orelse return NextError.AbyssUnderflow;
            defer popped.deinit(self.awacator);
            switch (popped) {
                .simple => {},
                .double => |bubbles| {
                    try self.abyss.appendSlice(self.awacator, bubbles.items);
                },
            }
        },
        .dpl => {
            const last = self.abyss.getLastOrNull() orelse return NextError.AbyssUnderflow;
            try self.abyss.append(self.awacator, try last.dupe(self.awacator));
        },
        .srn => |count| early: {
            if (count > self.abyss.items.len) return NextError.AbyssUnderflow;
            if (count == 0) {
                try self.abyss.append(self.awacator, .{ .double = .{} });
                break :early;
            }

            const double_bubble = try self.awacator.alloc(Bubble, count);
            errdefer self.awacator.free(double_bubble);

            @memcpy(double_bubble, self.abyss.items[self.abyss.items.len - count ..]);
            self.abyss.items.len -= count;
            self.abyss.appendAssumeCapacity(.{ .double = .fromOwnedSlice(double_bubble) });
        },
        .mrg => {
            var top = self.abyss.pop() orelse return NextError.AbyssUnderflow;
            defer top.deinit(self.awacator);
            var bottom = self.abyss.pop() orelse return NextError.AbyssUnderflow;
            defer bottom.deinit(self.awacator);

            switch (bottom) {
                .simple => |b| switch (top) {
                    .simple => |t| {
                        try self.abyss.append(self.awacator, .{ .simple = b +% t });
                    },
                    .double => |*t| {
                        try t.insert(self.awacator, 0, .{ .simple = b });
                        try self.abyss.append(self.awacator, .{ .double = t.* });
                        top = .{ .simple = undefined };
                    },
                },
                .double => |*b| {
                    switch (top) {
                        .simple => |t| try b.append(self.awacator, .{ .simple = t }),
                        .double => |t| try b.appendSlice(self.awacator, t.items),
                    }
                    try self.abyss.append(self.awacator, .{ .double = b.* });
                    bottom = .{ .simple = undefined };
                },
            }
        },
        .add, .sub, .mul, .div => {
            var top = self.abyss.pop() orelse return NextError.AbyssUnderflow;
            defer top.deinit(self.awacator);
            var bottom = self.abyss.pop() orelse return NextError.AbyssUnderflow;
            defer bottom.deinit(self.awacator);

            self.abyss.appendAssumeCapacity(try operate(
                self.awacator,
                top,
                bottom,
                switch (cmd) {
                    .add => .add,
                    .sub => .sub,
                    .mul => .mul,
                    .div => .mod, // Remainder first, than quotient on top
                    else => unreachable,
                },
            ));
            // Div must also append the quotient on top
            if (cmd == .div) {
                self.abyss.appendAssumeCapacity(try operate(self.awacator, top, bottom, .div));
            }
        },
        .cnt => {
            var bubble = self.abyss.pop() orelse return NextError.AbyssUnderflow;
            defer bubble.deinit(self.awacator);
            self.abyss.appendAssumeCapacity(.{ .simple = switch (bubble) {
                .simple => 0,
                .double => |b| @bitCast(@as(u32, @truncate(b.items.len))),
            } });
        },
        .jmp => |label| {
            self.pc = self.labels[label] orelse return NextError.JumpToUnlabbeled;
            return true;
        },
        .eql, .lss, .gr8 => {
            if (self.abyss.items.len < 2) return NextError.AbyssUnderflow;

            const top = switch (self.abyss.items[self.abyss.items.len - 1]) {
                .simple => |value| value,
                .double => return NextError.Invalid,
            };
            const bottom = switch (self.abyss.items[self.abyss.items.len - 2]) {
                .simple => |value| value,
                .double => return NextError.Invalid,
            };

            if (switch (cmd) {
                .eql => top != bottom,
                .lss => top >= bottom,
                .gr8 => top <= bottom,
                else => unreachable,
            }) {
                self.pc += 1;
            }
        },
        .trm => {
            self.pc = self.commands.len;
            return false;
        },
    }

    // Memory may or may not have been awacated. We must not fail from this
    // point onwards to prevent a memory leak.
    errdefer comptime unreachable;

    self.pc += 1;
    return true;
}

fn print(out: AnyWriter, bubble: Bubble) NextError!void {
    switch (bubble) {
        .simple => |char| {
            awascii.write(
                out,
                std.math.cast(u6, char) orelse return NextError.InvalidAwascii,
            ) catch return NextError.Unexpected;
        },
        .double => |double| {
            var it = std.mem.reverseIterator(double.items);
            while (it.next()) |inner_bubble| {
                try print(out, inner_bubble);
            }
        },
    }
}

fn printNum(out: AnyWriter, bubble: Bubble) NextError!void {
    switch (bubble) {
        .simple => |value| {
            out.print("{d}", .{value}) catch return NextError.Unexpected;
        },
        .double => |double| {
            var it = std.mem.reverseIterator(double.items);
            while (it.next()) |inner_bubble| {
                try printNum(out, inner_bubble);
                if (it.index > 0) out.writeByte(' ') catch return NextError.Unexpected;
            }
        },
    }
}

fn readAwascii(reader: AnyReader) NextError!u6 {
    while (true) {
        return awascii.read(reader) catch |e| switch (e) {
            error.InvalidByte => continue,
            else => return NextError.Unexpected,
        };
    }
}

fn operate(
    awacator: Awacator,
    top: Bubble,
    bottom: Bubble,
    op: enum { add, sub, mul, div, mod },
) NextError!Bubble {
    return blk: switch (top) {
        .simple => |t| switch (bottom) {
            .simple => |b| .{ .simple = switch (op) {
                .add => t +% b,
                .sub => t -% b,
                .mul => t *% b,
                .div => std.math.divFloor(i32, t, b) catch return NextError.MathError,
                .mod => std.math.mod(i32, t, b) catch return NextError.MathError,
            } },
            .double => |b| {
                var new_bubble: Bubble = .{ .double = try .initCapacity(awacator, b.items.len) };
                errdefer new_bubble.deinit(awacator);
                for (b.items) |bubble| {
                    new_bubble.double.appendAssumeCapacity(try operate(awacator, top, bubble, op));
                }
                break :blk new_bubble;
            },
        },
        .double => |t| switch (bottom) {
            .simple => {
                var new_bubble: Bubble = .{ .double = try .initCapacity(awacator, t.items.len) };
                errdefer new_bubble.deinit(awacator);
                for (t.items) |bubble| {
                    new_bubble.double.appendAssumeCapacity(try operate(awacator, bubble, bottom, op));
                }
                break :blk new_bubble;
            },
            .double => |b| {
                const len = @min(t.items.len, b.items.len);
                var new_bubble: Bubble = .{ .double = try .initCapacity(awacator, len) };
                errdefer new_bubble.deinit(awacator);
                for (t.items[t.items.len - len ..], b.items[b.items.len - len ..]) |t2, b2| {
                    new_bubble.double.appendAssumeCapacity(try operate(awacator, t2, b2, op));
                }
                break :blk new_bubble;
            },
        },
    };
}
