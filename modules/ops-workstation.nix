{ config, lib, pkgs, ... }: let
  cfg = config.nixops.opsWorkstation;
in {
  options.nixops.opsWorkstation = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Provision a machine as a nixops operator workstation: an unprivileged
        `ops` user with the toolchain (sops, age, ssh-to-age, gum,
        nixos-anywhere, deploy-rs) on PATH, flakes and the standard
        substituters, openssh key-only, passwordless sudo. Independent of
        the VM shape -- reusable on any host that should double as a
        control plane for a fleet.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "ops";
      description = "Unprivileged operator user name.";
    };

    uid = lib.mkOption {
      type = lib.types.int;
      default = 1000;
      description = ''
        Fixed uid for the operator user. Pinned so 9p host mounts can use
        dfltuid=<this> and the mount root ends up ops-owned without an
        extra chown step.
      '';
    };

    autologin = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Autologin the operator user on tty1/serial. Convenient for the
        ephemeral VM (`nix run <nixops>#opsvm`); turn off before reusing
        this module for anything long-lived.
      '';
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Additional packages to expose on the operator PATH.";
    };
  };

  config = lib.mkIf cfg.enable {
    nix.settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" cfg.user ];
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };

    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "prohibit-password";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
      };
    };

    users.users.${cfg.user} = {
      isNormalUser = true;
      uid = cfg.uid;
      extraGroups = [ "wheel" ];
      shell = pkgs.bash;
      # Empty password unlocks only the local console; sshd still refuses
      # password auth (disabled above) so remote access stays key-only.
      initialHashedPassword = "";
    };

    # Root exists for rescue only; no autologin, no fresh password.
    users.users.root.initialHashedPassword = "!";

    security.sudo.wheelNeedsPassword = false;

    services.getty.autologinUser = lib.mkIf cfg.autologin cfg.user;

    environment.systemPackages = (with pkgs; [
      git jq curl vim tmux less openssh
      sops age ssh-to-age
      gum
      nixos-anywhere
      deploy-rs
    ]) ++ cfg.extraPackages;

    environment.etc."motd".text = ''
      nixops operator workstation -- logged in as ${cfg.user}

      ~/.ssh and ~/.config/sops/age are mounted from the host state dir
      (opsvm-launch prints its path on start; default
      ~/.local/state/nixops-opsvm/ on the host). Anything you put there
      survives poweroff and VM rebuilds.

        1. Generate an ssh key for this operator identity:
             ssh-keygen -t ed25519 -C opsvm -f ~/.ssh/id_ed25519 -N ""
        2. Generate an age key for sops-nix:
             age-keygen -o ~/.config/sops/age/keys.txt
        3. Scaffold a fleet and drive it:
             nix run github:reflection-dev/nixops -- new my-fleet
             cd my-fleet && nix develop
             add-host <name>; install-host <name>; deploy <name>

      The ssh pubkey (id_ed25519.pub) and age recipient
      (age-keygen -y ~/.config/sops/age/keys.txt) from steps 1-2 are
      what the wizard prompts you for.
    '';
  };
}
