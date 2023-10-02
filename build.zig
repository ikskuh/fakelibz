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

pub const FakeLibraryOptions = struct {
    name: []const u8, // name of the library
    definition_file: std.Build.LazyPath, // this is the path to a fakelibz .def file
    target: std.zig.CrossTarget, // .target is non-optional, as fakelibz can only be used for cross-compilation and will not run on "local" machine
    version: ?std.SemanticVersion = null,
    link_libc: ?bool = null,
};

pub fn fakeLibrary(dep: *std.Build.Dependency, options: FakeLibraryOptions) *std.Build.CompileStep {
    if (options.target.isNative()) {
        @panic("Cannot use fakelibz to compile to native target. Please link the correct library when not cross-compiling!");
    }

    const implib_exe = dep.artifact("implib");

    const implib_gen = dep.builder.addRunArtifact(implib_exe);
    implib_gen.addFileArg(options.definition_file);
    const library_src = implib_gen.addOutputFileArg(dep.builder.fmt("{s}.zig", .{options.name}));

    const fake_lib = dep.builder.addSharedLibrary(.{
        .name = options.name,
        .root_source_file = library_src,
        .version = options.version,
        .target = options.target,
        .optimize = .ReleaseSmall,
        .link_libc = options.link_libc,
    });
    fake_lib.strip = false;

    // we must not provide compiler_rt symbols, otherwise the linker
    // will assume they exist in this lib and won't include the weak
    // ones in the executable!
    fake_lib.bundle_compiler_rt = false;

    return fake_lib;
}
