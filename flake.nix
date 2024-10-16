{
  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zls.url = "github:zigtools/zls";
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
      }: {
        packages.default = pkgs.stdenv.mkDerivation {
          name = "zigplug";
          src = ./.;

          inherit (inputs.zls.packages.${system}.zls) nativeBuildInputs;
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [self'.packages.default];
          packages = [inputs.zls.packages.${system}.zls];
        };
      };
    };
}
