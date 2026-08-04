{
  description = "nixops — generic NixOS fleet base: inventory-driven modules, deploy tooling, ops devShell";

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

  outputs = { self, nixpkgs, sops-nix, deploy-rs, ... }: {
    nixosModules.default = {
      imports = [
        sops-nix.nixosModules.sops
        ./modules
      ];
    };

    lib = {
      mkNixosConfigs = import ./lib/mkNixosConfigs.nix { inherit nixpkgs sops-nix self; };
      mkDeploy       = import ./lib/mkDeploy.nix       { inherit deploy-rs; };
    };

    # Populated later: lib.mkDevShell, templates.default, apps.<system>.new.
  };
}
