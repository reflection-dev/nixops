# Build the ops devShell an instance repo exposes as `nix develop`.
#
# Commands (bash scripts in ../scripts/, wrapped as writeShellApplication so
# shellcheck runs at build time and each command carries its own PATH):
#
#   ssh <name>             ssh via an ssh_config generated from the inventory
#   install-host <name>    nixos-anywhere + sops-recipient inject + secrets prompt
#   update-secrets [name]  interactive fill of any missing sops secrets
#
# More lands in follow-up commits (deploy, add-host, new wizard).
{ nixpkgs, deploy-rs }:
{ hosts, system, extraPackages ? [ ] }:
let
  pkgs = nixpkgs.legacyPackages.${system};

  sshConfig = pkgs.writeText "nixops-ssh-config" (
    builtins.concatStringsSep "\n" (nixpkgs.lib.mapAttrsToList (name: h: ''
      Host ${name}
        HostName ${h.ip}
        User root
    '') hosts)
  );

  ssh = pkgs.writeShellScriptBin "ssh" ''
    exec ${pkgs.openssh}/bin/ssh -F ${sshConfig} "$@"
  '';

  mkCmd = name: runtimeInputs: pkgs.writeShellApplication {
    inherit name runtimeInputs;
    text = builtins.readFile (../scripts + "/${name}.sh");
  };

  installHost = mkCmd "install-host" (with pkgs; [
    sops age ssh-to-age nixos-anywhere openssh jq gum
    nixVersions.latest
  ]);

  updateSecrets = mkCmd "update-secrets" (with pkgs; [
    sops jq gum
    nixVersions.latest
  ]);
in
pkgs.mkShell {
  packages = [
    ssh
    installHost
    updateSecrets
    deploy-rs.packages.${system}.deploy-rs
  ] ++ (with pkgs; [
    sops age ssh-to-age
    nixos-anywhere
    jq gum
  ]) ++ extraPackages;

  shellHook = ''
    echo "nixops devShell -- ${toString (builtins.length (builtins.attrNames hosts))} host(s) in inventory"
  '';
}
