const std = @import("std");

// https://refspecs.linuxfoundation.org/elf/elf.pdf

pub fn parseElfFile(
    input: std.fs.File,
    out_writer: anytype,
) !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allocator = arena.allocator();

    const argv = try std.process.argsAlloc(allocator);

    if (argv.len < 2 or argv.len > 3)
        @panic("usage: implib <input> [<output>]");

    const lib_path = argv[1];



    var buffered_out = std.io.bufferedWriter(out_writer);

    const writer = buffered_out.writer();

    // prepare elf:

    var elf = try std.elf.Header.read(input);

    var section_headers = elf.section_header_iterator(input);

    var dynamic_sections = std.ArrayList(std.elf.Elf64_Shdr).init(allocator);
    defer dynamic_sections.deinit();

    var strtabs = std.AutoArrayHashMap(u64, Strtab).init(allocator);
    defer strtabs.deinit();

    var symtabs = std.ArrayList(std.elf.Elf64_Shdr).init(allocator);
    defer symtabs.deinit();

    var dynsyms = std.ArrayList(std.elf.Elf64_Shdr).init(allocator);
    defer dynsyms.deinit();

    var shdrs = std.AutoArrayHashMap(u64, std.elf.Elf64_Shdr).init(allocator);
    defer shdrs.deinit();

    {
        var section_index: u64 = 0;
        while (try section_headers.next()) |section_hdr| : (section_index += 1) {
            try shdrs.putNoClobber(section_index, section_hdr);
            switch (section_hdr.sh_type) {
                std.elf.SHT_DYNAMIC => {
                    std.log.debug("process section of type SHT_DYNAMIC", .{});
                    try dynamic_sections.append(section_hdr);
                },
                std.elf.SHT_DYNSYM => {
                    std.log.debug("process section of type SHT_DYNSYM", .{});
                    try dynsyms.append(section_hdr);
                },
                std.elf.SHT_STRTAB => {
                    std.log.debug("process section of type SHT_STRTAB", .{});

                    const string = try allocator.allocSentinel(u8, section_hdr.sh_size, 0);

                    try input.seekTo(section_hdr.sh_offset);
                    try input.reader().readNoEof(string);

                    try strtabs.put(section_index, .{ .text = string });
                },
                std.elf.SHT_SYMTAB => {
                    std.log.debug("process section of type SHT_SYMTAB", .{});
                    try symtabs.append(section_hdr);
                },

                else => std.log.debug("ignoring section of type {}...", .{section_hdr.sh_type}),
            }
        }
    }

    const section_strings = strtabs.get(elf.shstrndx) orelse {
        std.log.err("file has bad section strings", .{});
        return 1;
    };

    if (dynamic_sections.items.len == 0) {
        std.log.err("file has no DYNAMIC section. is it even a dynamic object?!", .{});
        return 1;
    }
    if (dynamic_sections.items.len > 1) {
        std.log.warn("file has multiple DYNAMIC sections. Using just the first one...", .{});
    }

    const dynamic_section = dynamic_sections.items[0];

    // write output:

    try writer.print("#########################\n", .{});
    try writer.print("# {s}\n", .{std.fs.path.basename(lib_path)});
    try writer.print("#########################\n", .{});
    try writer.print("\n", .{});
    try writer.print("PATH {s}\n", .{lib_path}); // TODO: Print source file name
    try writer.print("\n", .{});

    {
        var path: []const u8 = lib_path;
        list_names: while (true) {
            try writer.print("NAME {s}\n", .{std.fs.path.basename(path)});

            var buffer: [std.os.PATH_MAX]u8 = undefined;
            var realpath = std.fs.cwd().readLink(path, &buffer) catch |err| switch (err) {
                error.FileNotFound => break :list_names,
                else => |e| return e,
            };

            path = realpath;
        }
        try writer.print("\n", .{});
    }

    // parse dynamic section and render deps:
    {
        var any_deps: bool = false;
        // SHT_DYNAMIC The section header index
        // of the string table used by
        // entries in the section.
        const strings = strtabs.get(dynamic_section.sh_link) orelse {
            std.log.err("DYNAMIC section sh_link is invalid!", .{});
            return 1;
        };

        var iter = ElfIterator(std.elf.Elf64_Dyn, std.elf.Elf32_Dyn).init(input, elf, dynamic_section);

        while (try iter.next()) |item| {
            const tag: DynTag = @enumFromInt(item.d_tag);
            const val: u64 = item.d_val;

            switch (tag) {
                .null => break,

                // This element holds the string table offset of a null-terminated string, giving
                // the name of the shared object. The offset is an index into the table recorded
                // in the DT_STRTAB entry. See "Shared Object Dependencies" below for
                // more information about these names.
                .soname => {
                    std.log.debug("soname = {s}", .{strings.get(val)});
                },

                // This element holds the string table offset of a null-terminated string, giving
                // the name of a needed library. The offset is an index into the table recorded
                // in the DT_STRTAB entry. See "Shared Object Dependencies'' for more
                // information about these names. The dynamic array may contain multiple
                // entries with this type. These entries' relative order is significant, though
                // their relation to entries of other types is not.
                .needed => {
                    try writer.print("DEP {s}\n", .{strings.get(val)});
                    any_deps = true;
                },

                // This element holds the address of the string table, described in Chapter 1.
                //Symbol names, library names, and other strings reside in this table.
                .strtab => {},

                // This element holds the address of the symbol table, described in
                // Chapter 1, with Elf32_Sym entries for the 32-bit class of files
                .symtab => {},

                // This element holds the size, in bytes, of the string table.
                .strsz => {},

                // This element holds the size, in bytes, of a symbol table entry.
                .syment => {},

                // This element holds the string table offset of a null-terminated search library
                // search path string, discussed in "Shared Object Dependencies". The offset
                // is an index into the table recorded in the DT_STRTAB entry.
                .rpath => {},

                else => std.log.debug("unhandled DYNAMIC entry {}: {}", .{ tag, val }),
            }
        }
        if (any_deps)
            try writer.writeAll("\n");
    }

    for (dynsyms.items) |section| {
        var iter = ElfIterator(std.elf.Elf64_Sym, std.elf.Elf32_Sym).init(input, elf, section);

        const strings = strtabs.get(dynamic_section.sh_link) orelse {
            std.log.err("DYNAMIC section sh_link is invalid!", .{});
            return 1;
        };

        while (try iter.next()) |sym| {
            const sym_name = sym.st_name;
            const sym_value = sym.st_value;
            const sym_size = sym.st_size;
            const sym_type = sym.st_type();
            const sym_bind = sym.st_bind();
            const sym_shndx = sym.st_shndx;

            const name = strings.get(sym_name);

            const sect = shdrs.get(sym_shndx) orelse {
                std.log.err("Symbol {s} has invalid shndx {}", .{ name, sym_shndx });
                continue;
            };

            const section_name = section_strings.get(sect.sh_name);

            // st_name  This member holds an index into the object file's symbol string table, which holds
            //          the character representations of the symbol names.
            // st_value This member gives the value of the associated symbol. Depending on the context,
            //          this may be an absolute value, an address, and so on; details appear below.
            // st_size  Many symbols have associated sizes. For example, a data object's size is the number
            //          of bytes contained in the object. This member holds 0 if the symbol has no size or
            //          an unknown size.
            // st_info  This member specifies the symbol's type and binding attributes. A list of the values
            //          and meanings appears below. The following code shows how to manipulate the
            //          values.

            switch (sym_bind) {

                //      Local symbols are not visible outside the object file containing their
                //      definition. Local symbols of the same name may exist in multiple files
                //      without interfering with each other.
                std.elf.STB_LOCAL => {
                    // local symbols are always ignored, we don't have to expose them
                    continue;
                },

                //      Global symbols are visible to all object files being combined. One file's
                //      definition of a global symbol will satisfy another file's undefined reference
                //      to the same global symbol.
                std.elf.STB_GLOBAL => {
                    //
                },

                //      Weak symbols resemble global symbols, but their definitions have lower
                //      precedence.
                std.elf.STB_WEAK => {
                    std.log.warn("TODO: Unhandled weak symbol {s}!", .{name});
                    continue;
                },

                else => std.log.warn("unhandled symbol binding: {}", .{sym_bind}),
            }

            switch (sym_type) {
                //  The symbol's type is not specified.
                std.elf.STT_NOTYPE => {},

                //  The symbol is associated with a data object, such as a variable, an array, and so on.
                std.elf.STT_OBJECT => {},

                //  The symbol is associated with a function or other executable code.
                std.elf.STT_FUNC => {},

                //  The symbol is associated with a section. Symbol table entries of this type exist primarily for relocation and normally have STB_LOCAL binding.
                std.elf.STT_SECTION => {
                    // We don't need and don't want to expose section symbols
                    continue;
                },

                else => std.log.warn("unhandled symbol type: {}", .{sym_type}),
            }

            switch (sym_shndx) {

                //  The symbol has an absolute value that will not change because of relocation.
                std.elf.SHN_ABS => {},

                // The symbol labels a common block that has not yet been allocated. The symbol's value gives alignment constraints, similar to a section's sh_addralign member. That is, the link editor will allocate the storage for the symbol at an address that is a multiple of st_value. The symbol's size tells how many bytes are required.
                std.elf.SHN_COMMON => {
                    std.log.warn("TODO: Unhandled COMMON symbol!", .{});
                    continue;
                },

                // This section table index means the symbol is undefined. When the link editor combines this object file with another that defines the indicated symbol, this file's references to the symbol will be linked to the actual definition.
                std.elf.SHN_UNDEF => {
                    // Those are imports from other libs
                    continue;
                },

                else => {},
            }

            if (sym_shndx == std.elf.SHN_ABS) {
                try writer.print("ABS {s} 0x{X:0>8}\n", .{ name, sym_value });
            } else {
                try writer.print("SYM {s} {s}\n", .{
                    section_name,
                    name,
                });
            }
            _ = sym_size;

            // std.log.info("name={} ({s}), value={}, size={}, type={}, bind={}", .{
            //     sym_name, name, sym_value, sym_size, sym_type, sym_bind,
            // });
        }
    }

    try buffered_out.flush();
    return 0;
}

pub fn ElfIterator(comptime T64: type, comptime T32: type) type {
    return struct {
        input: std.fs.File,
        elf: std.elf.Header,
        hdr: std.elf.Elf64_Shdr,
        offset: u64,

        pub fn init(input: std.fs.File, elf: std.elf.Header, sect: std.elf.Elf64_Shdr) @This() {
            return .{
                .input = input,
                .elf = elf,
                .hdr = sect,
                .offset = sect.sh_offset,
            };
        }

        pub fn next(self: *@This()) !?T64 {
            if (self.offset >= self.hdr.sh_offset + self.hdr.sh_size)
                return null;

            try self.input.seekTo(self.offset);

            const item = if (self.elf.is_64)
                try self.input.reader().readStruct(T64)
            else
                mapTo64(try self.input.reader().readStruct(T32));

            self.offset = try self.input.getPos();
            return item;
        }

        fn mapTo64(in: T32) T64 {
            const info32 = @typeInfo(T32).Struct;
            const info64 = @typeInfo(T64).Struct;
            if (info32.fields.len != info64.fields.len) @compileError("type mismatch");
            var out: T64 = std.mem.zeroes(T64);
            inline for (info32.fields) |fld| {
                @field(out, fld.name) = @field(in, fld.name);
            }
            return out;
        }
    };
}

// SHT_DYNAMIC	0x6	The section holds information for dynamic linking. Currently, an object file shall have only one dynamic section, but this restriction may be relaxed in the future. See `Dynamic Section' in Chapter 5 for details.
// SHT_DYNSYM	0xb	This section holds a minimal set of symbols adequate for dynamic linking. See also SHT_SYMTAB. Currently, an object file may have either a section of SHT_SYMTAB type or a section of SHT_DYNSYM type, but not both. This restriction may be relaxed in the future.
// SHT_FINI_ARRAY	0xf	This section contains an array of pointers to termination functions, as described in `Initialization and Termination Functions' in Chapter 5. Each pointer in the array is taken as a parameterless procedure with a void return.
// SHT_HASH	0x5	The section holds a symbol hash table. Currently, an object file shall have only one hash table, but this restriction may be relaxed in the future. See `Hash Table' in the Chapter 5 for details.
// SHT_HIPROC	0x7fffffff	Values in this inclusive range are reserved for processor-specific semantics.
// SHT_HIUSER	0xffffffff	This value specifies the upper bound of the range of indexes reserved for application programs. Section types between SHT_LOUSER and SHT_HIUSER can be used by the application, without conflicting with current or future system-defined section types.
// SHT_INIT_ARRAY	0xe	This section contains an array of pointers to initialization functions, as described in `Initialization and Termination Functions' in Chapter 5. Each pointer in the array is taken as a parameterless procedure with a void return.
// SHT_LOPROC	0x70000000	Values in this inclusive range are reserved for processor-specific semantics.
// SHT_LOUSER	0x80000000	This value specifies the lower bound of the range of indexes reserved for application programs.
// SHT_NOBITS	0x8	A section of this type occupies no space in the file but otherwise resembles SHT_PROGBITS. Although this section contains no bytes, the sh_offset member contains the conceptual file offset.
// SHT_NOTE	0x7	The section holds information that marks the file in some way. See `Note Section' in Chapter 5 for details.
// SHT_NULL	0x0	This value marks the section header as inactive; it does not have an associated section. Other members of the section header have undefined values.
// SHT_PREINIT_ARRAY	0x10	This section contains an array of pointers to functions that are invoked before all other initialization functions, as described in `Initialization and Termination Functions' in Chapter 5. Each pointer in the array is taken as a parameterless proceure with a void return.
// SHT_PROGBITS	0x1	The section holds information defined by the program, whose format and meaning are determined solely by the program.
// SHT_REL	0x9	The section holds relocation entries without explicit addends, such as type Elf32_Rel for the 32-bit class of object files or type Elf64_Rel for the 64-bit class of object files. An object file may have multiple relocation sections. See "Relocation"
// SHT_RELA	0x4	The section holds relocation entries with explicit addends, such as type Elf32_Rela for the 32-bit class of object files or type Elf64_Rela for the 64-bit class of object files. An object file may have multiple relocation sections. `Relocation' b
// SHT_SHLIB	0xa	This section type is reserved but has unspecified semantics.
// SHT_STRTAB	0x3	The section holds a string table. An object file may have multiple string table sections. See `String Table' below for details.
// SHT_SYMTAB	0x2	This section holds a symbol table. Currently, an object file may have either a section of SHT_SYMTAB type or a section of SHT_DYNSYM type, but not both. This restriction may be relaxed in the future. Typically, SHT_SYMTAB provides symbols for link editing, though it may also be used for dynamic linking. As a complete symbol table, it may contain many symbols unnecessary for dynamic linking.

const DynTag = enum(u32) {
    null = 0, // d_un = ignore, exe=mandatory, lib=mandatory
    needed = 1, // d_un = d_va, exe=optional, lib=optional
    pltrelsz = 2, // d_un = d_va, exe=optional, lib=optional
    pltgot = 3, // d_un = d_pt, exe=optional, lib=optional
    hash = 4, // d_un = d_pt, exe=mandatory, lib=mandatory
    strtab = 5, // d_un = d_pt, exe=mandatory, lib=mandatory
    symtab = 6, // d_un = d_pt, exe=mandatory, lib=mandatory
    rela = 7, // d_un = d_pt, exe=mandatory, lib=optional
    relasz = 8, // d_un = d_va, exe=mandatory, lib=optional
    relaent = 9, // d_un = d_va, exe=mandatory, lib=optional
    strsz = 10, // d_un = d_va, exe=mandatory, lib=mandatory
    syment = 11, // d_un = d_va, exe=mandatory, lib=mandatory
    init = 12, // d_un = d_pt, exe=optional, lib=optional
    fini = 13, // d_un = d_pt, exe=optional, lib=optional
    soname = 14, // d_un = d_va, exe=ignored, lib=optional
    rpath = 15, // d_un = d_va, exe=optional, lib=ignored
    symbolic = 16, // d_un = ignore, exe=ignored, lib=optional
    rel = 17, // d_un = d_pt, exe=mandatory, lib=optional
    relsz = 18, // d_un = d_va, exe=mandatory, lib=optional
    relent = 19, // d_un = d_va, exe=mandatory, lib=optional
    pltrel = 20, // d_un = d_va, exe=optional, lib=optional
    debug = 21, // d_un = d_pt, exe=optional, lib=ignored
    textrel = 22, // d_un = ignore, exe=optional, lib=optional
    jmprel = 23, // d_un = d_pt, exe=optional, lib=optional
    bind_now = 24, // d_un = ignore, exe=optional, lib=optional
    loproc = 0x70000000, // d_un = unspecifie, exe=unspecified, lib=unspecified
    hiproc = 0x7fffffff, // d_un = unspecifie, exe=unspecified, lib=unspecified

    _,
};

const Strtab = struct {
    text: [:0]u8,

    pub fn get(tab: Strtab, index: u64) [:0]const u8 {
        const ui: usize = @intCast(index);

        const end = std.mem.indexOfScalarPos(u8, tab.text, ui, 0) orelse tab.text.len;

        return tab.text[ui..end :0];
    }
};
