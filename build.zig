const std = @import("std");

pub fn build(b: *std.Build) !void {
    const parse_nm = b.addExecutable(.{
        .name = "parse-nm",
        .root_source_file = .{ .path = "src/parse-nm.zig" },
    });

    b.installArtifact(parse_nm);

    const implib = b.addExecutable(.{
        .name = "implib",
        .root_source_file = .{ .path = "src/implib.zig" },
    });

    b.installArtifact(implib);
}
