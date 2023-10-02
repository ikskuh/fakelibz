const std = @import("std");

pub fn main() !void {
    const argv = try std.process.argsAlloc(std.heap.page_allocator);

    if (argv.len < 1 or argv.len > 3)
        @panic("usage: implib [<input>] [<output>]");

    var input = if (argv.len >= 2)
        try std.fs.cwd().openFile(argv[1], .{})
    else
        std.io.getStdIn();
    defer input.close();

    var output = if (argv.len >= 3)
        try std.fs.cwd().createFile(argv[2], .{})
    else
        std.io.getStdOut();
    defer output.close();

    var buffered_in = std.io.bufferedReader(input.reader());
    var buffered_out = std.io.bufferedWriter(output.writer());

    const reader = buffered_in.reader();
    const writer = buffered_out.writer();

    try writer.writeAll(
        \\//! 
        \\//! This is autogenerated code!
        \\//!
        \\
    );

    while (true) {
        var line_buffer: [4096]u8 = undefined;

        var fbs = std.io.fixedBufferStream(&line_buffer);
        reader.streamUntilDelimiter(fbs.writer(), '\n', null) catch |err| switch (err) {
            error.EndOfStream => break,
            else => |e| return e,
        };

        const raw_line = fbs.getWritten();

        const line = std.mem.trim(
            u8,
            if (std.mem.indexOfScalar(u8, raw_line, '#')) |index|
                raw_line[0..index]
            else
                raw_line,
            " \t\r\n",
        );
        if (line.len == 0)
            continue;

        var parts = std.mem.tokenize(u8, line, " ");

        const kind_str = parts.next() orelse return error.InvalidFile;
        const kind = std.meta.stringToEnum(EntryKind, kind_str) orelse {
            std.log.err("found invalid line entry: '{}'", .{
                std.fmt.fmtSliceEscapeUpper(kind_str),
            });
            return error.InvalidFile;
        };

        switch (kind) {
            .NAME => {},
            .PATH => {},
            .VERSION => {},
            .DEP => {},
            .SYM => {
                const section = parts.next() orelse return error.InvalidFile;
                const symbol = parts.next() orelse return error.InvalidFile;

                if (std.mem.eql(u8, section, ".text")) {

                    // assume everything in .text is a function!

                    try writer.print(
                        "export fn {}() linksection(\"{}\") void {{ @panic(\"This is a dummy library!\"); }}\n",
                        .{
                            std.zig.fmtId(symbol),
                            std.zig.fmtEscapes(section),
                        },
                    );
                } else {
                    const is_const = std.mem.eql(u8, section, ".rodata");
                    try writer.print(
                        "export {s} {}: u8 linksection(\"{}\") align(16) = 0;\n",
                        .{
                            if (is_const) "const" else "var",
                            std.zig.fmtId(symbol),
                            std.zig.fmtEscapes(section),
                        },
                    );
                }
            },
            .ABS => @panic("absolute symbols not supported by implib yet!"),
        }
    }

    try buffered_out.flush();
}

const EntryKind = enum {
    PATH,
    NAME,
    VERSION,
    DEP,
    SYM,
    ABS,
};
