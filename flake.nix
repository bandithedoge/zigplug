{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    zig-overlay.url = "github:mitchellh/zig-overlay";
    zls.url = "github:zigtools/zls";
    zls.inputs.zig-overlay.follows = "zig-overlay";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];
      perSystem = {
        config,
        self',
        inputs',
        pkgs,
        system,
        ...
      }: let
        zig = inputs.zig-overlay.packages.${system}.master;
        inherit (inputs.zls.packages.${system}) zls;
      in {
        packages.default = pkgs.stdenv.mkDerivation {
          name = "zigplug";
          src = ./.;

          nativeBuildInputs = [
            zig
          ];
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [self'.packages.default];
          packages = [zls];
        };
      };
    };
}
