#!/bin/sh

libs="/nix/store/mgk70zgp61lcm141fcdbch7500cp6lm6-SDL2-2.26.5/lib/libSDL2.so /nix/store/lfvs703h0kzvwd4rh91z59zcl3ggzf1w-SDL2_image-2.6.3/lib/libSDL2_image.so /nix/store/a84qr1dyl4c9iw497xibix9v6ybvaj43-SDL2_ttf-2.20.2/lib/libSDL2_ttf.so"

set -euo pipefail

function print_alt_names()
{
    lib="$1"
    while [ -h "$lib" ]; do
        echo "NAME $(basename "$lib")"
        newlib="$(readlink "$lib")"
        if [ "$(dirname "$newlib")" == "." ]; then
            newlib="$(dirname "$lib")/$(basename "$newlib")"
        fi
        lib="$newlib"
    done
    [ -f "${lib}" ] || {
        echo "$lib is not a real file?!"
        return 1
    }
    echo "NAME $(basename "$lib")"
}

function print_dep_libs()
{
    readelf  -d "$1" | grep NEEDED | sed -re 's/.*\[(.*)\].*/DEP \1/'
}

function print_symbols()
{
    nm -P "${reallib}" | ./zig-out/bin/parse-nm
    echo ""
}

for lib in $libs; do

    reallib="$(realpath "${lib}")"

    name="$(basename "$lib")"
    name="${name%.so}"
    
    (
        echo "#########################"
        echo "# ${name}"
        echo "#########################"
        echo ""
        echo "PATH $(realpath --no-symlinks "$lib")"
        echo ""
        print_alt_names "$lib"
        echo ""
        print_dep_libs "$lib"
        echo ""
        print_symbols "${lib}"
    ) | tee "examples/${name}.def"

    ./zig-out/bin/implib < "examples/${name}.def" > "examples/${name}.zig"

    (
        cd examples
        zig build-lib -dynamic -target arm-linux-gnueabihf --name "${name#lib}" "${name}.zig"
        rm "${name}.so.o"
    )
done
