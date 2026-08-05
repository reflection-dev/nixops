---
title: "Writing host-specific modules"
time: "45 minutes"
---
# Writing host-specific modules

> **Prerequisite:** [Day-two operations](day-two-operations.md).
>
> **Outcome:** you can add a service to a single host; you can write a disko layout; you can extract a common module across hosts; you can override one of the nixops defaults for a single host.

The nixops base gives you a hardened but minimal NixOS: sshd,
firewall, root user with your keys, weekly GC, UTC. Everything
past that is your fleet's own. This chapter shows how to add it.

Everything below lives in `hosts/<name>/*.nix`, unless it is a
common piece worth extracting.

## Add a service: nginx, once

Say `web-1` should serve HTTP. In `hosts/web-1/default.nix`:

```nix
{ config, pkgs, ... }: {
  imports = [ ./hardware-configuration.nix ];

  services.nginx = {
    enable = true;
    recommendedGzipSettings   = true;
    recommendedOptimisation   = true;
    recommendedProxySettings  = true;
    recommendedTlsSettings    = true;
    virtualHosts."example.com" = {
      enableACME = true;                  # ACME (Let's Encrypt) TLS
      forceSSL   = true;
      root       = "/var/www/example.com";
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "ops@example.com";
  };

  nixops.firewall.allowedTCPPorts = [ 80 443 ];
}
```

Deploy:

```console
$ deploy web-1
```

That is it. No `apt-get install nginx`, no `certbot`, no
templating an `nginx.conf`. NixOS's `services.nginx` module
generates the config from the option values, the ACME module
requests certs, and the firewall module opens the ports.

Every option has documentation at
[search.nixos.org/options](https://search.nixos.org/options) --
look up `services.nginx` and see the full menu.

## Add a service to many hosts: extract a role

Two hosts both need a `node_exporter` for Prometheus scraping.
Instead of duplicating in each `hosts/<name>/default.nix`, extract:

```nix
# roles/node-exporter.nix
{ ... }: {
  services.prometheus.exporters.node = {
    enable = true;
    port   = 9100;
  };
  nixops.firewall.allowedTCPPorts = [ 9100 ];
}
```

Then pull it in from each host:

```nix
# hosts.nix
web-1 = { ip = "1.2.3.4"; modules = [ ./hosts/web-1 ../roles/node-exporter.nix ]; };
db-1  = { ip = "5.6.7.8"; modules = [ ./hosts/db-1  ../roles/node-exporter.nix ]; };
```

The paths above are illustrative; the exact layout is up to you.
Some fleets prefer a single `default.nix` per host that itself
imports role modules; both work.

## Override a nixops default for one host

Every base module has an `enable` option ([NixOS and the module system](../foundations/nixos-and-modules.md)). Turn one off
for a specific host:

```nix
# hosts.nix
console-1 = {
  ip = "9.9.9.9";
  modules = [ ./hosts/console-1 ];
  nixops.firewall.enable = false;              # this host is behind a physical firewall
};
```

Or override an option value:

```nix
edge-1 = {
  ip = "10.11.12.13";
  modules = [ ./hosts/edge-1 ];
  nixops.ssh.port = 2222;
};
```

Remember: the fields on the inventory entry become an inline
module fragment for that host ([Anatomy of an instance repo](../deploying/anatomy-of-an-instance.md)). If the change is more
than a few lines, write it in `hosts/edge-1/default.nix` instead
and reference it via `modules = [ ./hosts/edge-1 ]`.

## Write a disko layout

nixops pulls disko in as a flake input and imports its module for
every host, so `disko.devices` is available out of the box. During
`add-host` you either pick a preset (e.g. `hetzner-vm`) and get a
ready `hosts/<name>/disko.nix`, or pick `custom` and drop your own.

Full walkthrough with examples (single-disk ext4, ZFS mirror,
escape hatches, contributing a preset back) lives in
[Host files: disko, hardware-config, default.nix](../deploying/host-files.md).

## Add a user

Non-root users are the fleet's own concern (see
`modules/users.nix` -- only root's `authorized_keys` is managed by
the base). Add users in a per-host or per-role module:

```nix
# roles/app-user.nix
{ ... }: {
  users.users.app = {
    isSystemUser = true;
    group        = "app";
    home         = "/var/lib/app";
    createHome   = true;
  };
  users.groups.app = { };
}
```

For interactive human accounts:

```nix
users.users.alice = {
  isNormalUser = true;
  extraGroups  = [ "wheel" ];
  openssh.authorizedKeys.keys = [ "ssh-ed25519 ..." ];
};
```

## Wire up a systemd service using a secret

Full pattern: declare the secret, write a service unit that
consumes it, restart when the secret changes.

```nix
# hosts/web-1/default.nix
{ config, pkgs, ... }: {
  imports = [ ./hardware-configuration.nix ];

  sops.secrets.stripe_secret = {
    sopsFile = ../../secrets/web-1.yaml;
    owner    = "web-app";
    mode     = "0400";
  };

  systemd.services.web-app = {
    wantedBy = [ "multi-user.target" ];
    after    = [ "network.target" ];
    serviceConfig = {
      User            = "web-app";
      EnvironmentFile = config.sops.secrets.stripe_secret.path;
      ExecStart       = "${pkgs.web-app}/bin/web-app";
      Restart         = "on-failure";
    };
    restartTriggers = [ config.sops.secrets.stripe_secret.sopsFile ];
  };

  users.users.web-app.isSystemUser = true;
  users.users.web-app.group        = "web-app";
  users.groups.web-app = { };
}
```

- `sops.secrets.stripe_secret.path` is `/run/secrets/stripe_secret`.
- `restartTriggers = [ config.sops.secrets.stripe_secret.sopsFile ]`
  makes the service restart when the encrypted secret file changes
  (Nix hashes the `.sopsFile` path).
- After adding this to a module, run `update-secrets web-1` to
  populate the value, then `deploy web-1`.

## Add a package to a single host

```nix
# hosts/web-1/default.nix
{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    postgresql
    tmux
  ];
}
```

For the whole fleet, either extend the base module in nixops
itself, or wrap `mkNixosConfigs` in your fleet with a small
adapter that adds a shared `modules` fragment.

## Override a package version

To pin nginx to a specific version, use an overlay:

```nix
# flake.nix (outputs)
let
  pkgsOverride = final: prev: {
    nginx = prev.nginx.overrideAttrs (old: { version = "1.24.0"; src = ...; });
  };
in {
  nixosConfigurations = nixops.lib.mkNixosConfigs {
    inherit hosts sshKeys;
    # ... you would extend mkNixosConfigs to accept extraModules and pass
    #     { nixpkgs.overlays = [ pkgsOverride ]; }
  };
}
```

For a small change, `services.nginx.package = pkgs.nginxMainline;`
is often enough. Overlays get their own manual chapter:
[Nixpkgs Manual -- Overlays](https://nixos.org/manual/nixpkgs/stable/#chap-overlays).

## Add a scheduled task

```nix
{
  systemd.timers.backup = {
    wantedBy  = [ "timers.target" ];
    timerConfig.OnCalendar = "daily";
  };
  systemd.services.backup = {
    serviceConfig.Type = "oneshot";
    script = ''
      ${pkgs.restic}/bin/restic backup /var/lib/app
    '';
  };
}
```

Native systemd timers -- no cron file to template. NixOS's timer
module wraps this: see `services.cron` for classic cron, or the
[`services.borgbackup`](https://search.nixos.org/options?query=services.borgbackup)
option tree for a preset.

## Add a Docker or Podman container

```nix
{
  virtualisation.oci-containers = {
    backend = "podman";
    containers.grafana = {
      image = "grafana/grafana:11.4.0";
      ports = [ "3000:3000" ];
      environment = {
        GF_SECURITY_ADMIN_PASSWORD_FILE = "/run/secrets/grafana_admin";
      };
    };
  };
}
```

For anything that has a native NixOS module (Grafana does --
`services.grafana`), prefer that; you get option-checked config
and no image-provenance headache.

## Test locally before deploying

`deploy web-1 -- --dry-activate` builds + copies the closure to
the target but skips the final activation -- catches most breakage
without touching the running system. For pure-local iteration on
your workstation (no target involved yet), use plain Nix builders:

- `nix build .#nixosConfigurations.web-1.config.system.build.toplevel`
  -- build the whole system closure locally. Catches evaluation
  errors, missing packages, type errors on options.
- `nix build .#nixosConfigurations.web-1.config.system.build.vm && ./result/bin/run-web-1-vm`
  -- boot the config in a QEMU VM on your laptop. Great for
  services you can exercise without real hardware. See
  [NixOS Manual -- test VMs](https://nixos.org/manual/nixos/stable/#sec-nixos-tests).

Neither of these needs `nixos-rebuild`; the devShell already gives
you `nix`.

## Documenting host quirks

When a host has something nonstandard, drop a comment in its
module explaining why. `git blame` on `hosts/<name>/default.nix`
should tell the next operator (or you-in-six-months) why every
line is there.

## What next

You know how to add anything you would add on a Debian box, but
now it lives in git and deploys deterministically. [Troubleshooting](troubleshooting.md) is
the failure manual for when things do not work.

Next: [Troubleshooting](troubleshooting.md)

## References for this chapter

- [search.nixos.org/options](https://search.nixos.org/options) --
  every option NixOS ships; searchable.
- [search.nixos.org/packages](https://search.nixos.org/packages) --
  every package in Nixpkgs.
- [Zero to Nix -- writing NixOS modules](https://zero-to-nix.com/concepts/nixos)
  -- includes a service-adding walkthrough.
- [nix-community/disko](https://github.com/nix-community/disko)
- [Nixpkgs Manual -- Overlays](https://nixos.org/manual/nixpkgs/stable/#chap-overlays)
- [NixOS Wiki -- Systemd hardening](https://wiki.nixos.org/wiki/Systemd_Hardening)
  -- once you have services, harden them.
- [NixOS Wiki -- Cheatsheet](https://wiki.nixos.org/wiki/Cheatsheet)
- [NixOS Discourse -- "help wanted" category](https://discourse.nixos.org/c/learn/9)
  -- fastest way to get eyes on a config problem.
