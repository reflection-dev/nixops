{ lib, ... }: {
  imports = [
    ./nix-defaults.nix
    ./ssh.nix
    ./sops.nix
    ./users.nix
    ./firewall.nix
  ];

  options.nixops.host = {
    ip = lib.mkOption {
      type = lib.types.str;
      description = ''
        Public IP address of the host. Consumed by install/ops tooling
        (nixos-anywhere, deploy-rs, the devShell ssh alias) — NixOS itself
        gets its addressing from DHCP by default.
      '';
    };
  };
}
