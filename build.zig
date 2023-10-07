const std = @import("std");

pub fn build(b: *std.Build) !void {
    const args_dep = b.dependency("args", .{});
    const args_mod = args_dep.module("args");

    const fakelibz = b.addExecutable(.{
        .name = "fakelibz",
        .root_source_file = .{ .path = "src/fakelibz.zig" },
    });
    fakelibz.addModule("args", args_mod);
    b.installArtifact(fakelibz);
}

pub const FakeLibraryOptions = struct {
    name: []const u8, // name of the library
    definition_file: std.Build.LazyPath, // this is the path to a fakelibz .def file
    target: std.zig.CrossTarget, // .target is non-optional, as fakelibz can only be used for cross-compilation and will not run on "local" machine
    version: ?std.SemanticVersion = null,
    link_libc: ?bool = null,
};

pub fn fakeLibrary(dep: *std.Build.Dependency, options: FakeLibraryOptions) *std.Build.CompileStep {
    // if (options.target.isNative()) {
    //     @panic("Cannot use fakelibz to compile to native target. Please link the correct library when not cross-compiling!");
    // }

    const lib2zig_exe = dep.artifact("fakelibz");

    const gen_ziglib = dep.builder.addRunArtifact(lib2zig_exe);
    gen_ziglib.addArg("impl");
    gen_ziglib.addFileArg(options.definition_file);
    gen_ziglib.addArg("--output");
    const library_src = gen_ziglib.addOutputFileArg(dep.builder.fmt("{s}.zig", .{options.name}));

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
