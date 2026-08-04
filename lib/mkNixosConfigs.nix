# Build a `nixosConfigurations` attrset from a plain-data inventory.
#
# Inputs:
#   hosts   :: { <name> = { ip; system?; modules?; ...extraModuleFragment }; }
#   sshKeys :: [ "ssh-ed25519 ..." ... ]     shared across every host
#
# Each `hosts.<name>` entry is data -- its `modules` field lists NixOS module
# paths to import, and every other field becomes a NixOS-module fragment
# assigned into the resulting configuration (so `ip` is set as
# `nixops.host.ip`, arbitrary extras like `nixops.foo.enable = true` work
# naturally).
{ nixpkgs, sops-nix, self }:
{ hosts, sshKeys ? [ ] }:
let
  defaultSystem = "x86_64-linux";

  mkOne = name: hostData:
    let
      system    = hostData.system  or defaultSystem;
      extraMods = hostData.modules or [ ];
      # Everything except `system` and `modules` becomes an inline module
      # fragment. `ip` is mapped to `nixops.host.ip`.
      rest      = builtins.removeAttrs hostData [ "system" "modules" "ip" ];
      hostFrag  = { nixops.host.ip = hostData.ip; } // rest;
    in nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit sshKeys; };
      modules = [
        self.nixosModules.default
        { networking.hostName = name; }
        hostFrag
      ] ++ extraMods;
    };
in
builtins.mapAttrs mkOne hosts
