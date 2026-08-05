{
  description = "nixops -- generic NixOS fleet base: inventory-driven modules, deploy tooling, ops devShell";

  nixConfig = {
    extra-substituters = [ "https://nix-community.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, sops-nix, deploy-rs, ... }: let
    systems = [ "x86_64-linux" "aarch64-linux" ];
    forEachSystem = nixpkgs.lib.genAttrs systems;
  in {
    nixosModules.default = {
      imports = [
        sops-nix.nixosModules.sops
        ./modules
      ];
    };

    nixosModules.opsWorkstation = ./modules/ops-workstation.nix;

    lib = {
      mkNixosConfigs = import ./lib/mkNixosConfigs.nix { inherit nixpkgs sops-nix self; };
      mkDeploy       = import ./lib/mkDeploy.nix       { inherit deploy-rs; };
      mkDevShell     = import ./lib/mkDevShell.nix     { inherit nixpkgs deploy-rs; };
    };

    templates.default = {
      path = ./templates/default;
      description = "nixops instance -- new fleet scaffold";
    };

    packages = forEachSystem (system: {
      opsvm = (nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.opsWorkstation
          ({ modulesPath, ... }: {
            imports = [ "${modulesPath}/virtualisation/qemu-vm.nix" ];
            networking.hostName = "opsvm";
            system.stateVersion = "25.05";
            virtualisation = {
              memorySize = 4096;
              cores = 4;
              diskSize = 20000;
              graphics = false;
              forwardPorts = [
                { from = "host"; host.port = 2222; guest.port = 22; }
              ];
            };
          })
        ];
      }).config.system.build.vm;
    });

    apps = forEachSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        newCmd = pkgs.writeShellApplication {
          name = "new";
          runtimeInputs = with pkgs; [
            gum age git gawk gnused coreutils findutils
            nixVersions.latest
          ];
          text = ''
            export TEMPLATE_DIR="${./templates/default}"
          '' + builtins.readFile ./scripts/new.sh;
        };
        newApp = { type = "app"; program = "${newCmd.out}/bin/new"; };
        opsvmApp = {
          type = "app";
          program = "${self.packages.${system}.opsvm}/bin/run-opsvm-vm";
        };
      in {
        new = newApp;
        default = newApp;
        opsvm = opsvmApp;
      });
  };
}
