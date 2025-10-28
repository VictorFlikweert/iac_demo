{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;

      # pkgs set for each supported system
      pkgsFor = forAllSystems (system: nixpkgs.legacyPackages.${system});
    in {
      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor.${system};
        in {
          default = pkgs.mkShellNoCC {
            packages = [ pkgs.salt-lint ];
          };
        });
    };
}
