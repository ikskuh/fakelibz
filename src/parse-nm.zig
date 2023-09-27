const std = @import("std");

pub fn main() !void {
    var buffered_in = std.io.bufferedReader(std.io.getStdIn().reader());
    var buffered_out = std.io.bufferedWriter(std.io.getStdOut().writer());

    const reader = buffered_in.reader();
    const writer = buffered_out.writer();

    while (true) {
        var line_buffer: [4096]u8 = undefined;

        var fbs = std.io.fixedBufferStream(&line_buffer);
        reader.streamUntilDelimiter(fbs.writer(), '\n', null) catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };

        const line = fbs.getWritten();

        const symbol = parseSymbol(line) catch |err| {
            std.log.err("invalid line({s}): '{}'", .{ @errorName(err), std.zig.fmtEscapes(line) });
            continue;
        };

        errdefer std.log.err("bad symbol: {s} {} {} {s}", .{ @tagName(symbol.type), symbol.value, symbol.size, symbol.name });

        if (symbol.type.isUndefined())
            continue;

        if (symbol.type.isLocal())
            continue;

        const section = switch (symbol.type) {
            .global_absolute => ".abs",
            .global_bss => ".bss",
            .global_data => ".data",
            .global_text => ".text",
            .global_rodata => ".rodata",
            else => return error.BadSymbol,
        };

        if (symbol.type == .global_absolute) {
            try writer.print("ABS {s} 0x{X:0>8}\n", .{
                symbol.name,
                symbol.value,
            });
        } else {
            try writer.print("SYM {s} {s}\n", .{
                section,
                symbol.name,
            });
        }
    }

    try buffered_out.flush();
}

const Symbol = struct {
    name: []const u8,
    type: Type,
    value: u64,
    size: u64,

    const Type = enum(u8) {
        // TODO: Port more items: https://sourceware.org/binutils/docs/binutils/nm.html

        global_text = 'T', // A global text symbol.
        global_data = 'D', // A global symbol naming initialized data.
        global_rodata = 'R', // A read-only data symbol.
        global_bss = 'B', // A global "bss" (uninitialized data) symbol.

        local_text = 't', // A local text symbol.
        local_data = 'd', // A local data symbol.
        local_rodata = 'r', // A local read-only data symbol.
        local_bss = 'b', // A local "bss" (uninitialized data) symbol.

        weak_object = 'V', // A weak object.
        weak_reference = 'W', // A weak reference.

        global_absolute = 'A', // A global, absolute symbol.
        common_symbol = 'C', // A "common" symbol, representing uninitialized data.
        debugger = 'N', // A debugger symbol.
        undefined = 'U', // An undefined symbol.
        local_absolute = 'a', // A local absolute symbol.
        undefined_weak_object = 'v', // A weak object that is undefined.
        undefined_weak_symbol = 'w', // A weak symbol that is undefined.
        other = '?', // None of the above.

        pub fn isUndefined(t: Type) bool {
            return switch (t) {
                .undefined => true,
                .undefined_weak_object => true,
                .undefined_weak_symbol => true,
                else => false,
            };
        }

        pub fn isGlobal(t: Type) bool {
            return std.ascii.isUpper(@intFromEnum(t));
        }

        pub fn isLocal(t: Type) bool {
            return std.ascii.isLower(@intFromEnum(t));
        }
    };
};
fn parseSymbol(line: []const u8) !Symbol {
    var spliter = std.mem.split(u8, line, " ");

    const sym_name_str = spliter.next() orelse return error.MissingName;
    const sym_type_str = spliter.next() orelse return error.MissingType;
    const sym_value_str = spliter.next() orelse return error.MissingValue;
    const sym_size_str = spliter.next() orelse return error.MissingSize;

    if (sym_type_str.len != 1)
        return error.InvalidType;

    return Symbol{
        .name = sym_name_str,
        .type = try std.meta.intToEnum(Symbol.Type, sym_type_str[0]),
        .value = try std.fmt.parseInt(u64, sym_value_str, 16),
        .size = try std.fmt.parseInt(u64, sym_size_str, 16),
    };
}
