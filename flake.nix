{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zig-overlay = {
      url = "github:bandithedoge/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin"];
      perSystem = {
        pkgs,
        system,
        ...
      }: let
        zig' = inputs.zig-overlay.packages.${system}.default;
      in {
        devShells.default = pkgs.mkShell {
          packages = [
            zig'
            zig'.zls
          ];
        };
      };
    };

  nixConfig = {
    extra-substituters = ["https://zigplug.cachix.org"];
    extra-trusted-public-keys = ["zigplug.cachix.org-1:RQ1LcVcTwuhlNt0P39IBG46qRfMdPR3WS1Rm7SUu8rw="];
  };
}
