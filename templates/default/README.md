# my-fleet

NixOS fleet, powered by [nixops](https://github.com/reflection-dev/nixops).

## Getting started

    nix develop

Inside the shell:

    add-host web-1       # prompts for ip; scaffolds hosts/web-1/
    install-host web-1   # nixos-anywhere + sops recipient + first secrets
    ssh web-1            # via generated ssh_config from hosts.nix
    deploy               # deploy-rs to every host in hosts.nix
    update-secrets       # interactively fill any missing sops secrets

## SSH keys

Shared across every host -- edit the `sshKeys = [...]` list in `flake.nix`.

## SOPS

Admin recipient(s) live in `.sops.yaml`. Each host gets its own age
recipient (derived from its ssh_host_ed25519_key by `install-host`);
that plus the admin(s) can decrypt `secrets/<host>.yaml`.
