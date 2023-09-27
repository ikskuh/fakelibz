{pkgs ? import <nixpkgs> {}}: let
  vhs = import ./vhs.nix;
in
  pkgs.mkShell {
    nativeBuildInputs = [
      # zig
      pkgs.zig_0_11

      # debugging
      pkgs.llvmPackages_16.bintools
    ];
    buildInputs = [];
    shellHook = ''
      # put your shell hook here
    '';
  }
