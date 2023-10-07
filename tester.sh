#!/bin/sh

clear

set -euo pipefail

libs="/nix/store/mgk70zgp61lcm141fcdbch7500cp6lm6-SDL2-2.26.5/lib/libSDL2.so /nix/store/lfvs703h0kzvwd4rh91z59zcl3ggzf1w-SDL2_image-2.6.3/lib/libSDL2_image.so /nix/store/a84qr1dyl4c9iw497xibix9v6ybvaj43-SDL2_ttf-2.20.2/lib/libSDL2_ttf.so /nix/store/inmc4n9sdrhgzwj739mvpf99h29z4xcm-libdrm-2.4.115/lib/libdrm.so /nix/store/sw6dywwgvalklwajvzjpgh2wwdn90cvj-glfw-3.3.8/lib/libglfw.so.3"

zig build 

for lib in $libs; do

    echo "process ${lib}"
    ./zig-out/bin/implib "${lib}"

done
