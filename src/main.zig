const std = @import("std");
const Awa = @import("Awa.zig");
const Awatizer = @import("Awatizer.zig");

const HELP_MSG =
    \\Usage: awa5zig [options]
    \\
    \\Reads an AWA5.0 program from stdin and runs it.
    \\
    \\Options:
    \\  -f <file>  Read the program from a file instead of stdin
    \\  -h         Show this help message
    \\
;

const AwaError = error{
    FailedToFlush,
    FailedToOpenFile,
    MissingArgument,
} ||
    Awa.FromAwaStreamError ||
    Awa.NextError;

pub fn main() void {
    runMain() catch |e| hawandleNonexistantErrors(e);
}

fn runMain() AwaError!void {
    const awacator = std.heap.smp_allocator;

    var program: Awa = blk: {
        const file, const is_file = try getInput(awacator);
        defer if (is_file) file.close();
        var tokens: Awatizer = .init(file.reader().any());
        break :blk try .fromAwaStream(awacator, &tokens);
    };
    defer program.deinit();

    const stdin = std.io.getStdIn().reader().any();
    const stdout_raw = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_raw);
    const stdout = bw.writer().any();

    while (try program.next(stdin, stdout)) {
        if (bw.end > 0) bw.flush() catch return AwaError.FailedToFlush;
    }
}

fn getInput(awacator: std.mem.Allocator) AwaError!struct { std.fs.File, bool } {
    var args = try std.process.argsWithAllocator(awacator);
    defer args.deinit();

    _ = args.skip(); // Skip process name
    while (args.next()) |arg| {
        if (std.mem.eql(u8, "-f", arg)) {
            const path = args.next() orelse return AwaError.MissingArgument;
            return .{
                std.fs.cwd().openFile(path, .{}) catch return AwaError.FailedToOpenFile,
                true,
            };
        } else if (std.mem.eql(u8, "-h", arg)) {
            std.io.getStdErr().writeAll(HELP_MSG) catch {};
            std.process.exit(0);
        }
    }
    return .{ std.io.getStdIn(), false };
}

// Never used frfr no cap 🧢
fn hawandleNonexistantErrors(e: AwaError) noreturn {
    switch (e) {
        error.OutOfMemory => @panic("Go download more RAM"),
        error.Unexpected => @panic("Awa!?"),

        Awatizer.NextError.NoInitialAwa => @panic("No awa's? 🤨"),
        Awatizer.NextError.EndOfStream => @panic("Awaw-"),

        Awa.NextError.AbyssUnderflow => @panic("Oops, almost popped that cherry"),
        Awa.NextError.Invalid => @panic("Go directly to awa jail. Do not pawass GO. Do not collect $200"),
        Awa.NextError.InvalidAwascii => @panic("Sussy Awascii"),
        Awa.NextError.JumpToUnlabbeled => @panic("Jelly fell into the void"),
        Awa.NextError.MathError => @panic("I hate mawth"),

        AwaError.FailedToFlush => @panic("Someone clogged the toilet"),
        AwaError.FailedToOpenFile => @panic("404 awa not found"),
        AwaError.MissingArgument => @panic("Missing awagument"),
    }
}

fn runTest(
    awacator: std.mem.Allocator,
    program_bytes: []const u8,
    in: std.io.AnyReader,
    out: std.io.AnyWriter,
) AwaError!void {
    var fbs: std.io.FixedBufferStream([]const u8) = .{ .buffer = program_bytes, .pos = 0 };
    var awatizer: Awatizer = .init(fbs.reader().any());

    var program: Awa = try .fromAwaStream(awacator, &awatizer);
    defer program.deinit();

    while (try program.next(in, out)) {}
}

test "test programs" {
    const allocator = std.testing.allocator;
    const expectOutput = std.testing.expectEqualStrings;

    var input_buf: std.io.FixedBufferStream([]const u8) = .{ .buffer = "", .pos = 0 };
    const input = input_buf.reader().any();

    var output_buf: std.ArrayList(u8) = .init(allocator);
    defer output_buf.deinit();
    const output = output_buf.writer().any();

    output_buf.clearRetainingCapacity();
    try runTest(allocator, @embedFile("test-input/F.awa"), undefined, output);
    try expectOutput("F", output_buf.items);

    output_buf.clearRetainingCapacity();
    try runTest(allocator, @embedFile("test-input/loop.awa"), undefined, output);
    try expectOutput(
        \\Jelly Hoshiumi
        \\Jelly Hoshiumi
        \\Jelly Hoshiumi
        \\Jelly Hoshiumi
        \\Jelly Hoshiumi
        \\
    , output_buf.items);

    input_buf.reset();
    input_buf.buffer = "10\n";
    output_buf.clearRetainingCapacity();
    try runTest(allocator, @embedFile("test-input/fib.awa"), input, output);
    try expectOutput(
        \\1
        \\1
        \\2
        \\3
        \\5
        \\8
        \\13
        \\21
        \\34
        \\55
        \\
    , output_buf.items);
}
