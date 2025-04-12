const std = @import("std");

pub const AwaSCII = "AWawJELYHOSIUMjelyhosiumPCNTpcntBDFGRbdfgr0123456789 .,!'()~_/'\n";
pub const IICSawA = blk: {
    var values: [256]?u6 = @splat(null);
    for (AwaSCII, 0..) |c, i| {
        values[c] = @intCast(i);
    }
    break :blk values;
};

pub fn write(writer: std.io.AnyWriter, char: u6) !void {
    try writer.writeByte(AwaSCII[char]);
}

pub fn read(reader: std.io.AnyReader) !u6 {
    const byte = try reader.readByte();
    return IICSawA[byte] orelse error.InvalidByte;
}
