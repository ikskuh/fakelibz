#!/bin/sh

libs="/nix/store/mgk70zgp61lcm141fcdbch7500cp6lm6-SDL2-2.26.5/lib/libSDL2.so /nix/store/lfvs703h0kzvwd4rh91z59zcl3ggzf1w-SDL2_image-2.6.3/lib/libSDL2_image.so /nix/store/a84qr1dyl4c9iw497xibix9v6ybvaj43-SDL2_ttf-2.20.2/lib/libSDL2_ttf.so"

set -e 

for lib in $libs; do
    name="$(basename "$lib")"
    name="${name%.so}"
    
    (
        echo "#########################"
        echo "# ${name}"
        echo "#########################"
        echo ""
        readelf  -d $lib | grep NEEDED | sed -re 's/.*\[(.*)\].*/DEP \1/'
        echo ""
        nm -P "${lib}" | ./zig-out/bin/parse-nm
    ) | tee "examples/${name}.def"

    ./zig-out/bin/implib < "examples/${name}.def" > "examples/${name}.zig"

    (
        cd examples
        zig build-lib -dynamic -target arm-linux-gnueabihf --name "${name#lib}" "${name}.zig"
        rm "${name}.so.o"
    )
done
