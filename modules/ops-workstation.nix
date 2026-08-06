{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.nixops.opsWorkstation;
in
{
  options.nixops.opsWorkstation = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Provision a machine as a nixops operator workstation: an unprivileged
        `ops` user with the toolchain (sops, age, ssh-to-age, gum,
        nixos-anywhere, deploy-rs, openssh client) on PATH, flakes and
        the standard substituters, passwordless sudo. No inbound sshd
        by default -- the workstation initiates outbound ssh only.
        Independent of the VM shape -- reusable on any host that should
        double as a control plane for a fleet.
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
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      # Accept flake nixConfig without the interactive "do you want to
      # allow configuration setting ..." prompt. Scoped to this operator
      # module -- must NOT land in the base fleet modules, where hosts
      # run untrusted flakes and blanket trust is a footgun.
      accept-flake-config = true;
      trusted-users = [
        "root"
        cfg.user
      ];
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };

    users.users.${cfg.user} = {
      isNormalUser = true;
      uid = cfg.uid;
      extraGroups = [ "wheel" ];
      shell = pkgs.zsh;
      # Empty password unlocks only the local console; sshd still refuses
      # password auth (disabled above) so remote access stays key-only.
      initialHashedPassword = "";
    };

    # Root exists for rescue only; no autologin, no fresh password.
    users.users.root.initialHashedPassword = "!";

    security.sudo.wheelNeedsPassword = false;

    services.getty.autologinUser = lib.mkIf cfg.autologin cfg.user;

    environment.systemPackages =
      (with pkgs; [
        git
        jq
        curl
        vim
        tmux
        less
        openssh
        sops
        age
        ssh-to-age
        gum
        nixos-anywhere
        deploy-rs
      ])
      ++ cfg.extraPackages;

    # Interactive shell: zsh with the two must-have plugins (fish-style
    # ghost autosuggestions from history, and syntax highlighting as
    # you type). Shell scripts still run in their shebang's interpreter
    # (bash, sh, ...), so the tooling is unaffected.
    programs.zsh = {
      enable = true;
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
      enableCompletion = true;
      histSize = 10000;
      # INTERACTIVE_COMMENTS: treat `# ...` at a prompt as a comment
      # (like bash does by default) so operators can paste annotated
      # command snippets without zsh throwing "command not found: #".
      interactiveShellInit = ''
        setopt INTERACTIVE_COMMENTS
      '';
    };
    # Provision an empty ~/.zshrc so zsh-newuser-install (the
    # "New Z Shell configuration" wizard) skips on first login --
    # the actual config comes from /etc/zshrc (programs.zsh above).
    systemd.tmpfiles.rules = [
      "f /home/${cfg.user}/.zshrc 0644 ${cfg.user} users -"
    ];

    # Auto-load per-project devShells on `cd`. With nix-direnv, the
    # scaffolded .envrc (`use flake`) puts the whole flake devShell on
    # PATH the first time the operator enters a fleet directory.
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    # Cross-shell prompt with git/nix context. Named ANSI colours so
    # the terminal emulator's theme owns the actual RGB -- change the
    # theme, prompt follows. Compact two-line layout: context on top,
    # the input character alone on the bottom line.
    programs.starship = {
      enable = true;
      settings = {
        add_newline = true;
        format = "$directory$git_branch$git_status$nix_shell$line_break$character";
        character = {
          success_symbol = "[>](bold cyan)";
          error_symbol = "[>](bold red)";
        };
        directory = {
          style = "bold blue";
          truncation_length = 3;
          truncate_to_repo = false;
        };
        git_branch = {
          symbol = "";
          style = "purple";
          format = "[$symbol$branch]($style) ";
        };
        git_status = {
          style = "yellow";
          format = "[$all_status$ahead_behind]($style) ";
        };
        nix_shell = {
          style = "cyan";
          format = "[$symbol$state]($style) ";
          impure_msg = "nix";
          pure_msg = "nix";
          unknown_msg = "";
          heuristic = true;
        };
      };
    };

    environment.etc."motd".text = ''
      nixops operator workstation -- logged in as ${cfg.user}

      ~/.ssh, ~/.config/sops/age and ~/workdir are mounted from the
      host state dir (opsvm-launch prints its path on start; default
      ~/.local/state/nixops-opsvm/<name>/). Anything you put in them
      survives poweroff and VM rebuilds.

      You land in ~/workdir on login. Scaffold a fleet there when you
      are ready -- name it after this VM so tooling stays consistent:

        new $(hostname)
        cd $(hostname) && nix develop
             add-host <name>; install-host <name>; deploy <name>

      The ssh pubkey (id_ed25519.pub) and age recipient
      (age-keygen -y ~/.config/sops/age/keys.txt) from steps 1-2 are
      what the wizard prompts you for.
    '';
  };
}
