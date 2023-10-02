# fakelibz

Implementor of stub libraries to allow cross-os linking without having an actual sysroot present.

## Definition File Format

The file is a line-oriented format that uses simple, space separated items. Use `#` to introduce line comments.

The following line patterns are available:

```sh
PATH    <path>                    # full <path> from which the def file was originally created
NAME    <basename>                # <basename> of original file, can be multiple if the original file was symlinked/aliased.
VERSION <major>.<minor>.<patch>   # version of the shared object
DEP     <name>                    # dependencies declared by the original file
SYM     <section> <name>          # Declares a symbol <name> that was originally found in <section>.
ABS     <name> <value>            # Declares an absolute symbol <name> with the given integer <value>.
```

The spacing between each item is arbitrary, but must be at least a single `SP` character. Lines are terminated by either `LF` or `CR LF` and can use indentation with either `SP` or `TAB` characters.

The files are encoded in `UTF-8` encoding.
