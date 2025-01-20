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
      perSystem = {pkgs, ...}: {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            zig
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
