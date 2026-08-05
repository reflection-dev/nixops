---
time: "45 minutes"
---
# 05 -- NixOS and the module system

> **Prerequisite:** [Chapter 4](flakes.md).
>
> **Outcome:** you can read every module in `modules/`; you know how options merge; you can look up any NixOS option in the manual and understand its type.

NixOS is what you get when you point Nix's evaluator at "a whole
operating system" instead of "a package". Everything about a running
system -- systemd units, users, `/etc/*`, the boot loader, the
kernel -- is one attribute set produced by evaluating a set of
modules. The module system is how that set gets assembled.

If you learn nothing else from this chapter: **a NixOS configuration
is not a script**. It is a value. Rebuilding a system is
"evaluate that value; realise it; switch the running system's
symlink". Nothing is done "step by step" the way Ansible does.

## The one-picture model

A NixOS configuration is the result of merging every module in the
`modules` list into a single big attribute set. Each module can:

- **`imports`** other modules (add more to the merge);
- declare **`options`** (schema entries -- "here is an option
  `services.nginx.enable` of type bool");
- set **`config`** values (values for options declared anywhere in
  the merge).

The evaluator walks every module, gathers every option declaration,
gathers every config value, checks the config values against the
declared types, merges them (with configurable priorities), and
produces the final `config` value. That value is what
`nixos-rebuild` uses to build `/etc/systemd/system/*`,
`/nix/store/...-etc/*`, everything.

## The simplest module

```
{ config, lib, pkgs, ... }:
{
  services.openssh.enable = true;
}
```

A file that returns an attribute set with `services.openssh.enable =
true;`. The `{ config, lib, pkgs, ... }:` at the top is the module
system's calling convention: every module is a function receiving
those bindings and returning the config.

You do not have to accept every argument. `{ ... }: { ... }` is a
valid module too. But `config`, `lib`, `pkgs`, and `options` are the
four you will use.

## The three parts of a full module

```
{ config, lib, pkgs, ... }: let
  cfg = config.myapp;
in {
  imports = [ ./sub-module.nix ];

  options.myapp = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable myapp.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "TCP port for myapp.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.myapp = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig.ExecStart = "${pkgs.myapp}/bin/myapp --port ${toString cfg.port}";
    };
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
```

- **`imports`** pulls in more modules.
- **`options.myapp = { ... }`** declares two options under the
  attribute path `myapp.enable` and `myapp.port`.
- **`config = lib.mkIf cfg.enable { ... }`** sets configuration
  values *only if* `cfg.enable` is true. Under a disabled module,
  the whole `config` attribute contributes nothing.

Notice `cfg = config.myapp`. `config` inside a module is *the final
merged config* -- what every other module sees. Reading from it lets
your module react to what has been set (including its own options).
This is safe because of lazy evaluation.

## `mkOption`

Every option declaration follows the same shape:

```
lib.mkOption {
  type = lib.types.<TYPE>;
  default = <VALUE>;                     # optional
  description = ''What this option does'';
  example = <VALUE>;                     # optional; shows up in docs
}
```

Types you will see in this repo:

- `lib.types.bool`
- `lib.types.int` / `lib.types.port`
- `lib.types.str`
- `lib.types.package` -- a Nix package
- `lib.types.path` -- a filesystem path
- `lib.types.listOf T` -- a list of `T`
- `lib.types.attrsOf T` -- an attribute set with values of `T`
- `lib.types.nullOr T` -- `T` or `null`
- `lib.types.submodule { options = { ... }; }` -- nested option
  schema

Full list: [NixOS Manual -- Option types](https://nixos.org/manual/nixos/stable/#sec-option-types).

## `mkIf`, `mkDefault`, `mkForce`, `mkOverride`

The module system merges option values from every module that sets
them. When you need to control *how* your value merges:

- **`lib.mkIf cond value`** -- include `value` in the merge only if
  `cond` is true. If false, this module contributes nothing here.
- **`lib.mkDefault value`** -- set at low priority. Any other
  module setting the same option without `mkDefault` wins.
- **`lib.mkForce value`** -- set at high priority. Wins against
  ordinary and `mkDefault`. Use sparingly.
- **`lib.mkOverride N value`** -- set at explicit priority `N`
  (lower N wins). `mkDefault` is 1000, ordinary is 100, `mkForce` is
  50. Only reach for `mkOverride` if you need a non-standard
  priority.

Most of the time you will only write `mkIf` and, once in a while,
`mkForce`.

## How lists and attribute sets merge

Non-primitive types have built-in merges:

- Lists concatenate. `allowedTCPPorts = [ 80 ]` in one module and
  `allowedTCPPorts = [ 443 ]` in another yields `[ 80 443 ]` in the
  final config. This is why every module can add to
  `environment.systemPackages` without stepping on the others.
- Attribute sets merge recursively. Two modules can each set some
  keys in `services.nginx.virtualHosts` and they combine.

If you set the *same key of an attribute set* in two modules, you
get an error unless one uses `mkDefault` / `mkForce` / `mkOverride`.

## Reading this repo's modules

Open [`modules/`](../modules/). The aggregator [`modules/default.nix`](../modules/default.nix)
is the shortest:

```
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
      description = ''Public IP address of the host. Consumed by install/ops tooling ...'';
    };
  };
}
```

Two things happen here:

- Every base module is imported. Loading `default.nix` loads them
  all.
- One option is declared: `nixops.host.ip`. It has no default (the
  operator must provide one; `mkNixosConfigs` writes it from the
  `ip = ...` field in `hosts.nix`).

Then [`modules/ssh.nix`](../modules/ssh.nix):

```
{ config, lib, ... }: let
  cfg = config.nixops.ssh;
in {
  options.nixops.ssh = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''Enable openssh, key-only, root login with key permitted.'';
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 22;
      description = ''TCP port for sshd.'';
    };
  };

  config = lib.mkIf cfg.enable {
    services.openssh = {
      enable = true;
      ports = [ cfg.port ];
      settings = {
        PermitRootLogin = "prohibit-password";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
      };
      openFirewall = true;
    };
  };
}
```

The pattern is: declare a `nixops.<name>.enable` (defaulted to
`true` for the sane cases), wrap the whole `config` block in
`lib.mkIf cfg.enable`. Any host can opt out by setting
`nixops.<name>.enable = false;` in its own module.

`modules/nix-defaults.nix` is a longer example of the same shape.
Read it end-to-end; it should look boringly familiar by now.

## `imports`, revisited

`imports = [ ... ]` accepts:

- **Paths** (`./ssh.nix`) -- Nix reads and evaluates the file.
- **Attribute sets** -- treated as inline modules.
- **Functions** matching the module signature.

You can inline a module without a separate file:

```
imports = [
  { services.nginx.enable = true; }
];
```

`mkNixosConfigs` uses this to inject `networking.hostName = name;`
and the per-host inventory fields as an inline module for each
host.

## `specialArgs`

When you build a NixOS configuration with `nixpkgs.lib.nixosSystem`,
you can pass `specialArgs = { foo = ...; }` -- those become extra
arguments to every module. This repo passes `sshKeys`:

```
lib/mkNixosConfigs.nix:
  nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = { inherit sshKeys; };
    modules = [ ... ];
  };
```

Then `modules/users.nix`:

```
{ sshKeys, ... }: {
  users.users.root.openssh.authorizedKeys.keys = sshKeys;
}
```

`sshKeys` is not an option; it is a value handed to every module.
`specialArgs` is the right tool when data has to reach many modules
and turning it into an option would be overkill.

Reference: [NixOS Manual -- writing modules](https://nixos.org/manual/nixos/stable/#sec-writing-modules).

## Finding options: the NixOS Option Search

If you ever need to know "does NixOS have an option for X?", the
answer is almost always yes. Two lookups:

- **Search UI**: [search.nixos.org/options](https://search.nixos.org/options).
- **Manual list**: [NixOS Manual -- Configuration Options](https://nixos.org/manual/nixos/stable/options.html).

Every entry gives you the type, default, description, and the file
in Nixpkgs where it is declared.

## Building a configuration

Concept-wise: a NixOS configuration becomes a live system by having
its derivations built, its store paths realised, and its activation
script run. In this repo you never invoke that flow by hand -- the
devShell wraps it:

- `install-host <name>` for the very first install of a target
  (Chapter 7).
- `deploy [name]` for every subsequent change (Chapter 8).

Under the hood these are `nixos-anywhere` and `deploy-rs`
respectively, both of which end up calling activation scripts that
NixOS builds from your modules -- the same activation NixOS's
built-in `nixos-rebuild` would run locally. You will only need to
know about `nixos-rebuild` for two edge cases: recovering a host
from its console when SSH is broken, or local testing on a NixOS
workstation (Chapter 12).

Reference: [NixOS Manual -- nixos-rebuild](https://nixos.org/manual/nixos/stable/#sec-nixos-rebuild).

## What next

You now have the whole language stack: Nix, flakes, and the module
system. The next two chapters cover the tools this fleet base is
built around -- sops-nix for secrets (6), nixos-anywhere for
bootstrap (7), and deploy-rs for continuous deploys (8) -- so that
Chapter 9 can put them together with a full end-to-end walkthrough
of the ops loop.

Next: [Chapter 6 -- Secrets with sops-nix.](../deploying/sops-nix.md)

## References for this chapter

- [NixOS Manual -- Writing modules](https://nixos.org/manual/nixos/stable/#sec-writing-modules)
- [NixOS Manual -- Option types](https://nixos.org/manual/nixos/stable/#sec-option-types)
- [search.nixos.org/options](https://search.nixos.org/options) -- the
  option index. Bookmark it.
- [NixOS Manual -- module examples](https://nixos.org/manual/nixos/stable/#sec-writing-modules-example)
- [Zero to Nix -- NixOS](https://zero-to-nix.com/concepts/nixos) --
  Determinate Systems' friendly overview of NixOS and how modules
  compose.
- [NixOS Wiki -- NixOS modules](https://wiki.nixos.org/wiki/NixOS_modules)
  -- community-maintained examples and idioms.
- [NixOS Discourse](https://discourse.nixos.org/) -- the main
  community forum. Almost every module question you have has already
  been asked and answered here.
- [Nix Pills, chapter 20](https://nixos.org/guides/nix-pills/nixpkgs-parameters.html)
  -- if you want to see how modules were bootstrapped from the raw
  language.
