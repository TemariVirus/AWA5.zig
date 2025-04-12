const std = @import("std");

reader: std.io.AnyReader,
state: State = .start,

const AWA = 0;
const WA = 1;

pub const Awatism = union(enum) {
    command: CommandType,
    param_u5: u5,
    param_i8: i8,
};

pub const CommandType = enum(u5) {
    nop = 0x00,
    prn,
    pr1,
    red,
    r3d,
    blw,
    sbm,
    pop,
    dpl,
    srn,
    mrg,
    add,
    sub,
    mul,
    div,
    cnt,
    lbl,
    jmp,
    eql,
    lss,
    gr8,

    trm = 0x1F,
};

pub const State = enum {
    start,
    expect_command,
    expect_param_u5,
    expect_param_i8,
    terminated,
};

pub const NextError = error{
    NoInitialAwa,
    EndOfStream,
};

pub fn init(reader: std.io.AnyReader) @This() {
    return .{ .reader = reader };
}

/// Return the next awatism token, or `null` if the stream is exhausted.
pub fn next(self: *@This()) !?Awatism {
    loop: switch (self.state) {
        .start => {
            if (!self.readInitialAwa()) return NextError.NoInitialAwa;
            continue :loop .expect_command;
        },
        .expect_command => {
            const awa = self.readInt(u5) orelse {
                self.state = .terminated;
                return null;
            };
            const command = std.meta.intToEnum(CommandType, awa) catch continue :loop .expect_command;
            self.state = switch (command) {
                .nop,
                .prn,
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
                => .expect_command,
                .sbm, .srn, .lbl, .jmp => .expect_param_u5,
                .blw => .expect_param_i8,
            };
            return .{ .command = command };
        },
        .expect_param_u5 => {
            self.state = .expect_command;
            return .{ .param_u5 = self.readInt(u5) orelse return NextError.EndOfStream };
        },
        .expect_param_i8 => {
            self.state = .expect_command;
            return .{ .param_i8 = self.readInt(i8) orelse return NextError.EndOfStream };
        },
        .terminated => return null,
    }
}

fn readChar(self: @This()) ?enum { a, w, space } {
    while (true) {
        const char = self.reader.readByte() catch return null;
        switch (char) {
            'A', 'a' => return .a,
            'W', 'w' => return .w,
            ' ' => return .space,
            else => continue,
        }
    }
}

fn readInitialAwa(self: @This()) bool {
    loop: switch (self.readChar() orelse return false) {
        .a => switch (self.readChar() orelse return false) {
            .w => switch (self.readChar() orelse return false) {
                .a => return true,
                else => |token| continue :loop token,
            },
            else => |token| continue :loop token,
        },
        else => continue :loop self.readChar() orelse return false,
    }
}

fn readBit(self: @This()) ?u1 {
    // I wonder if there's any way to build a comptime trie that turns into
    // this switch? 🤔
    loop: switch (self.readChar() orelse return null) {
        .a => continue :loop self.readChar() orelse return null,
        .w => switch (self.readChar() orelse return null) {
            .a => return WA,
            else => |token| continue :loop token,
        },
        .space => switch (self.readChar() orelse return null) {
            .a => switch (self.readChar() orelse return null) {
                .w => switch (self.readChar() orelse return null) {
                    .a => return AWA,
                    else => |token| continue :loop token,
                },
                else => |token| continue :loop token,
            },
            else => |token| continue :loop token,
        },
    }
}

fn readInt(self: @This(), comptime Int: type) ?Int {
    var awa: Int = 0;
    for (0..@bitSizeOf(Int)) |_| {
        awa <<= 1;
        awa |= self.readBit() orelse return null;
    }
    return awa;
}
