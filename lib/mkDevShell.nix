# Build the ops devShell an instance repo exposes as `nix develop`.
#
# First slice: an `ssh` wrapper that reads a config generated from the
# inventory, plus the CLI tooling every fleet operator ends up wanting
# (sops, age, ssh-to-age, deploy-rs, nixos-anywhere, jq, gum).
#
# Follow-up commits add install-host, update-secrets, deploy, add-host,
# and the `new` wizard on top.
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
in
pkgs.mkShell {
  packages = [
    ssh
    deploy-rs.packages.${system}.deploy-rs
  ] ++ (with pkgs; [
    sops age ssh-to-age
    nixos-anywhere
    jq
    gum
  ]) ++ extraPackages;

  shellHook = ''
    echo "nixops devShell -- ${toString (builtins.length (builtins.attrNames hosts))} host(s) in inventory"
  '';
}
