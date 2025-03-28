{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zig2nix.url = "github:Cloudef/zig2nix";
  };

  outputs = inputs @ {
    flake-parts,
    zig2nix,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];
      perSystem = {
        pkgs,
        system,
        ...
      }: let
        zigEnv = zig2nix.zig-env.${system} {
          zig = zig2nix.packages.${system}.zig-master;
        };
      in {
        devShells.default = zigEnv.mkShell {
          packages = with pkgs; [
            zls

            libGL
            pixman
            pkg-config
            xorg.libX11
            xorg.libXext
            xorg.libXrender
          ];
        };
      };
    };
}
