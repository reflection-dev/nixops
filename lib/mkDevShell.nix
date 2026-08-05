# Build the ops devShell an instance repo exposes as `nix develop`.
#
# Commands (bash scripts in ../scripts/, wrapped as writeShellApplication so
# shellcheck runs at build time and each command carries its own PATH):
#
#   ssh <name>                 ssh via an ssh_config generated from the inventory
#   install-host <name>        nixos-anywhere + sops-recipient inject + secrets prompt
#   update-secrets [name]      interactive fill of any missing sops secrets
#   set-secret <h> <k> <file>  non-interactive: write one secret from file or stdin
#   deploy [name]              deploy-rs wrapper; all hosts, or one by name
#   add-host <name>            interactive: prompt for IP, scaffold host dir, append to hosts.nix
#
# The `new` wizard for scaffolding a whole fleet lands separately as an
# app (`nix run <nixops> -- new <fleet>`).
{ nixpkgs, deploy-rs }:
{
  hosts,
  system,
  extraPackages ? [ ],
}:
let
  pkgs = nixpkgs.legacyPackages.${system};

  sshConfig = pkgs.writeText "nixops-ssh-config" (
    builtins.concatStringsSep "\n" (
      nixpkgs.lib.mapAttrsToList (name: h: ''
        Host ${name}
          HostName ${h.ip}
          User root
      '') hosts
    )
  );

  ssh = pkgs.writeShellScriptBin "ssh" ''
    exec ${pkgs.openssh}/bin/ssh -F ${sshConfig} "$@"
  '';

  mkCmd =
    name: runtimeInputs:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = builtins.readFile (../scripts + "/${name}.sh");
    };

  installHost = mkCmd "install-host" (
    with pkgs;
    [
      sops
      age
      ssh-to-age
      nixos-anywhere
      openssh
      jq
      gum
      nixVersions.latest
    ]
  );

  updateSecrets = mkCmd "update-secrets" (
    with pkgs;
    [
      sops
      jq
      gum
      nixVersions.latest
    ]
  );

  setSecret = mkCmd "set-secret" (
    with pkgs;
    [
      sops
      jq
      gum
      coreutils
      nixVersions.latest
    ]
  );

  deployCmd = pkgs.writeShellApplication {
    name = "deploy";
    runtimeInputs = [
      deploy-rs.packages.${system}.deploy-rs
      pkgs.gum
    ];
    text = builtins.readFile ../scripts/deploy.sh;
  };

  addHost = pkgs.writeShellApplication {
    name = "add-host";
    runtimeInputs = with pkgs; [
      gum
      gawk
      coreutils
    ];
    # Nix-store path to the disko presets tree, injected so add-host can `cp`
    # a chosen preset (e.g. Hetzner Cloud VM) into hosts/<name>/disko.nix
    # without knowing where nixops itself lives on the host filesystem.
    text = ''
      export DISKO_PRESETS_DIR="${../templates/disko}"
    ''
    + builtins.readFile ../scripts/add-host.sh;
  };
in
pkgs.mkShell {
  packages = [
    ssh
    installHost
    updateSecrets
    setSecret
    deployCmd
    addHost
  ]
  ++ (with pkgs; [
    sops
    age
    ssh-to-age
    nixos-anywhere
    jq
    gum
  ])
  ++ extraPackages;

  shellHook = ''
    echo "nixops devShell -- ${toString (builtins.length (builtins.attrNames hosts))} host(s) in inventory"
  '';
}
