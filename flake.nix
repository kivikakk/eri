{
  description = "eri";

  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-23.11;
    flake-utils.url = github:numtide/flake-utils;
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
      inherit (pkgs) ruby_3_3 lib;
    in {
      formatter = pkgs.alejandra;

      devShells.default = let
        env = pkgs.bundlerEnv {
          name = "eri-bundler-env";
          ruby = ruby_3_3;
          gemfile = ./Gemfile;
          lockfile = ./Gemfile.lock;
          gemset = import ./gemset.nix;
        };
      in
      pkgs.mkShell { 
        name = "eri";
        buildInputs = [
          ruby_3_3 env
        ];
      };
    });
}
