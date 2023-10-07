pub const std = @import("std");
pub const args_parser = @import("args");

const Verb = union(enum) {
    impl: struct {
        output: ?[]const u8 = null,
    },
    elf: struct {
        output: ?[]const u8 = null,
    },
    dll: struct {
        // TODO: PE not supported yet
        output: ?[]const u8 = null,
    },
};

const Options = struct {
    help: bool = false,

    pub const shorthands = .{
        .h = "help",
    };

    pub const meta = .{
        .usage_summary = "[-h] <verb> [<verb options>...]",
        .full_text =
        \\fakelibz is a tool to create faked implementations of shared object files with Zig.
        \\
        \\The generated libraries will expose the same symbols as another library, but will only contain stub implementations. This way, one can link against such a library *without* having it actually present.
        ,

        .option_docs = .{
            .help = "Prints this help.",
        },
    };
};

fn printUsage(cli: args_parser.ParseArgsResult(Options, Verb), out: std.fs.File) !void {
    try args_parser.printHelp(
        Options,
        cli.executable_name orelse "fakelibz",
        out.writer(),
    );

    try out.writer().writeAll(
        \\
        \\Verbs:
        \\
        \\  impl [<def>] [--output <file>]
        \\
        \\      Generates a Zig implementation of the <def> file. If <def> is not present, the definition will be read from stdin.
        \\
        \\      -o, --output <file>     Instad of writing to stdout, the generated output will be written to <file>.
        \\
        \\  elf <file> [--output <def>]
        \\
        \\      Converts a real library <file> into a fake one.
        \\
        \\      -o, --output <def>      Instead of writing to stdout, the generated fakelib will be written to <def>.
        \\
        \\  dll <file> [--output <def>]
        \\
        \\      Converts a real library <file> into a fake one.
        \\
        \\      -o, --output <def>      Instead of writing to stdout, the generated fakelib will be written to <def>.
        \\
        \\
    );
}

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    var cli = args_parser.parseWithVerbForCurrentProcess(Options, Verb, allocator, .print) catch return 1;
    defer cli.deinit();

    if (cli.options.help) {
        try printUsage(cli, std.io.getStdOut());
        return 0;
    }

    const verb = cli.verb orelse {
        try printUsage(cli, std.io.getStdErr());
        return 1;
    };

    switch (verb) {
        .impl => |vals| {
            if (cli.positionals.len > 1) {
                try printUsage(cli, std.io.getStdErr());
                return 1;
            }

            var input = if (cli.positionals.len > 0)
                try std.fs.cwd().openFile(cli.positionals[0], .{})
            else
                std.io.getStdIn();
            defer input.close();

            var output = if (vals.output) |output_file|
                try std.fs.cwd().createFile(output_file, .{})
            else
                std.io.getStdOut();
            defer output.close();

            try @import("lib2zig.zig").generateZigImplementation(
                input.reader(),
                output.writer(),
            );

            return 0;
        },
        .elf => |vals| {
            if (cli.positionals.len != 1) {
                try printUsage(cli, std.io.getStdErr());
                return 1;
            }

            var output = if (vals.output) |output_file|
                try std.fs.cwd().createFile(output_file, .{})
            else
                std.io.getStdOut();
            defer output.close();

            var input = try std.fs.cwd().openFile(cli.positionals[0], .{});
            defer input.close();

            return try @import("elfgen.zig").parseElfFile(
                input,
                output.writer(),
            );
        },
        .dll => {
            std.log.err("TODO: DLL conversion not implemented yet!", .{});
            return 1;
        },
    }
}
