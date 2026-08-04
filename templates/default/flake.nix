{
  description = "my-fleet";  # NIXOPS_DESCRIPTION

  inputs = {
    nixops.url = "github:reflection-dev/nixops";

    nixpkgs.follows   = "nixops/nixpkgs";
    sops-nix.follows  = "nixops/sops-nix";
    deploy-rs.follows = "nixops/deploy-rs";
  };

  outputs = { self, nixops, nixpkgs, deploy-rs, ... }: let
    system = "x86_64-linux";
    hosts  = import ./hosts.nix;

    # Shared across every host (root's authorized_keys). Grow this into
    # ./admins.nix with a proper submodule when per-person options are
    # needed (email, editor, roles, ...).
    sshKeys = [
      # NIXOPS_SSH_KEYS_START
      # "ssh-ed25519 AAAA... you@laptop"
      # NIXOPS_SSH_KEYS_END
    ];
  in {
    nixosConfigurations = nixops.lib.mkNixosConfigs { inherit hosts sshKeys; };
    deploy.nodes        = nixops.lib.mkDeploy self.nixosConfigurations;
    checks.${system}    = deploy-rs.lib.${system}.deployChecks self.deploy;

    devShells.${system}.default = nixops.lib.mkDevShell {
      inherit hosts system;
    };
  };
}
