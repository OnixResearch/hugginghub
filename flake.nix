{
  description = "HuggingHub — self-hosted Hugging Face Hub, packaged for NixOS";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg: (pkg.pname or "") == "hugginghub";
        };
    in
    {
      packages = lib.genAttrs systems (
        system:
        let
          hugginghub = (pkgsFor system).callPackage ./nix/package.nix { };
        in
        {
          inherit hugginghub;
          default = hugginghub;
        }
      );

      # Same module under both names so importers can use either.
      nixosModules = {
        default = ./nix/module.nix;
        hugginghub = ./nix/module.nix;
      };

      checks = lib.genAttrs systems (system: {
        module-eval = (pkgsFor system).callPackage ./nix/eval.nix {
          nixosSystem = lib.nixosSystem;
          module = self.nixosModules.default;
          inherit system;
        };
      });
    };
}
