{
  description = "eri";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-23.11;
    flake-utils.url = github:numtide/flake-utils;
    zig = {
      url = github:mitchellh/zig-overlay;
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-utils,
    ...
  }: let
    overlays = [
      (final: prev: {
        zig-overlay = inputs.zig.packages.${prev.system};
      })
    ];
  in
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit overlays system;};
      inherit (pkgs) lib;
      zig =
        if pkgs.stdenv.isDarwin
        then pkgs.zig-overlay.master
        else pkgs.zig;
    in rec {
      formatter = pkgs.alejandra;

      packages.default = pkgs.stdenv.mkDerivation {
        name = "eri";

        src = ./.;

        nativeBuildInputs = [zig];

        buildInputs = [zig];

        dontAddExtraLibs = true;

        preBuild = ''
          export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig"
        '';
      };

      checks.default = packages.default;

      devShells.default = packages.default;
    });
}
