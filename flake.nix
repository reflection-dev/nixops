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

    packages = forEachSystem (system: let
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
    in {
      new = newCmd;
      opsvm = (nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          self.nixosModules.opsWorkstation
          ({ modulesPath, pkgs, ... }: {
            imports = [ "${modulesPath}/virtualisation/qemu-vm.nix" ];
            # Fallback hostname; the real one comes from the launcher's
            # -fw_cfg name=opt/opsvm/hostname,string=<name> and gets
            # applied by opsvm-hostname.service before getty.
            networking.hostName = "opsvm";
            system.stateVersion = "25.05";
            virtualisation = {
              memorySize = 4096;
              cores = 4;
              diskSize = 20000;
              graphics = false;
            };
            # qemu_fw_cfg exposes /sys/firmware/qemu_fw_cfg/by_name/... so
            # the wrapper can push the requested hostname without a mount.
            boot.kernelModules = [ "qemu_fw_cfg" ];
            systemd.services.opsvm-hostname = {
              description = "Apply hostname pushed via QEMU fw_cfg";
              wantedBy = [ "sysinit.target" ];
              before = [ "network-pre.target" "systemd-user-sessions.service" "getty.target" ];
              after = [ "sys-firmware-qemu_fw_cfg.mount" ];
              unitConfig.ConditionPathExists = "/sys/firmware/qemu_fw_cfg/by_name/opt/opsvm/hostname/raw";
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
              path = with pkgs; [ coreutils ];
              script = ''
                name=$(tr -d '[:space:]' < /sys/firmware/qemu_fw_cfg/by_name/opt/opsvm/hostname/raw)
                if [ -n "$name" ]; then
                  echo "$name" > /proc/sys/kernel/hostname
                  echo "$name" > /etc/hostname
                fi
              '';
            };
            # Bind-mount /mnt/opsvm-fleet -> /home/ops/<HOSTNAME> at boot,
            # so the shared fleet directory appears at ~/<hostname> for
            # the ops user (the hostname is only known at runtime, so a
            # static fileSystems entry cannot use it directly).
            systemd.services.opsvm-fleet-bind = {
              description = "Bind-mount opsvm fleet to /home/ops/<hostname>";
              wantedBy = [ "multi-user.target" ];
              after = [ "mnt-opsvm\\x2dfleet.mount" "opsvm-hostname.service" ];
              requires = [ "opsvm-hostname.service" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
              };
              path = with pkgs; [ coreutils util-linux ];
              script = ''
                hn=$(cat /proc/sys/kernel/hostname)
                if [ -z "$hn" ] || [ "$hn" = "(none)" ]; then
                  echo "opsvm-fleet-bind: no hostname yet, skipping" >&2
                  exit 0
                fi
                target="/home/ops/$hn"
                mkdir -p "$target"
                chown ops:users "$target"
                if ! mountpoint -q "$target"; then
                  mount --bind /mnt/opsvm-fleet "$target"
                fi
              '';
            };
            # 9p mounts backed by the host state dir (opsvm-launch wraps
            # run-opsvm-vm with matching -virtfs args). nofail so a bare
            # run-opsvm-vm invocation still boots to a login prompt.
            # dfltuid/dfltgid map an empty mapped-xattr mount root to the
            # ops user (uid 1000, primary group `users` gid 100), so no
            # post-mount chown is needed.
            fileSystems."/home/ops/.ssh" = {
              device = "opsssh";
              fsType = "9p";
              options = [ "trans=virtio" "version=9p2000.L" "cache=loose" "nofail" "msize=104857600" "dfltuid=1000" "dfltgid=100" ];
              neededForBoot = false;
            };
            fileSystems."/home/ops/.config/sops/age" = {
              device = "opsage";
              fsType = "9p";
              options = [ "trans=virtio" "version=9p2000.L" "cache=loose" "nofail" "msize=104857600" "dfltuid=1000" "dfltgid=100" ];
              neededForBoot = false;
            };
            fileSystems."/mnt/opsvm-fleet" = {
              device = "opsfleet";
              fsType = "9p";
              options = [ "trans=virtio" "version=9p2000.L" "cache=loose" "nofail" "msize=104857600" "dfltuid=1000" "dfltgid=100" ];
              neededForBoot = false;
            };
            # Parent dirs of the age mount -- systemd creates the leaf
            # mountpoint but not intermediate directories.
            systemd.tmpfiles.rules = [
              "d /home/ops/.config       0755 ops users -"
              "d /home/ops/.config/sops  0755 ops users -"
            ];
            # `new` on PATH so the first-login hook can run it offline;
            # git defaults so `new` can `git commit` the scaffold without
            # asking the operator for identity first.
            environment.systemPackages = [ newCmd ];
            programs.git = {
              enable = true;
              config = {
                init.defaultBranch = "main";
                user = {
                  name = "ops";
                  email = "ops@opsvm";
                };
              };
            };
            # First-login: auto-provision the ops identity and scaffold the
            # fleet at ~/<hostname> if it does not exist yet. Sourced by
            # every login shell, but each step is a no-op after the first
            # time.
            environment.etc."profile.d/opsvm-firstlogin.sh".text = ''
              # shellcheck shell=sh
              if [ "$(id -un)" = "ops" ]; then
                hn=$(hostname)
                fleet_dir="$HOME/$hn"
                if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
                  echo "opsvm: generating ~/.ssh/id_ed25519"
                  ssh-keygen -t ed25519 -C "opsvm-$hn" -f "$HOME/.ssh/id_ed25519" -N "" >/dev/null
                fi
                if [ ! -f "$HOME/.config/sops/age/keys.txt" ]; then
                  echo "opsvm: generating ~/.config/sops/age/keys.txt"
                  age-keygen -o "$HOME/.config/sops/age/keys.txt" 2>/dev/null
                fi
                if [ -d "$fleet_dir" ] && [ ! -f "$fleet_dir/flake.nix" ]; then
                  echo "opsvm: scaffolding fleet '$hn' at $fleet_dir"
                  (cd "$HOME" && new "$hn")
                fi
                if [ -d "$fleet_dir" ]; then
                  cd "$fleet_dir" || true
                fi
                unset hn fleet_dir
              fi
            '';
          })
        ];
      }).config.system.build.vm;
    });

    apps = forEachSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        newApp = { type = "app"; program = "${self.packages.${system}.new}/bin/new"; };
        opsvmLauncher = pkgs.writeShellApplication {
          name = "opsvm-launch";
          runtimeInputs = with pkgs; [ coreutils ];
          text = ''
            export RAW_VM="${self.packages.${system}.opsvm}"
          '' + builtins.readFile ./scripts/opsvm-launch.sh;
        };
        opsvmApp = { type = "app"; program = "${opsvmLauncher}/bin/opsvm-launch"; };
      in {
        new = newApp;
        default = newApp;
        opsvm = opsvmApp;
      });
  };
}
