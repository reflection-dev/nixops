---
time: "30 minutes"
---
# 10 -- Anatomy of an instance repo

> **Prerequisite:** [Your first fleet](your-first-fleet.md) (you have a scaffolded fleet repo).
>
> **Outcome:** you can point at any file in the fleet repo and say what it does, why it exists, and when you edit it.

The `nix run ... -- new` wizard scaffolds five files. Everything
after that is what you add. This chapter is the reference for those
five, plus the `hosts/<name>/` subtrees you grow into.

Open your fleet repo alongside this chapter.

## File tree

```text
my-fleet/
|-- flake.nix           inputs + outputs (nixosConfigurations, deploy.nodes, devShell)
|-- hosts.nix           plain-data inventory
|-- .sops.yaml          age recipients + creation rules
|-- .gitignore
|-- README.md
|-- hosts/              per-host modules (grow as you add hosts)
|   `-- web-1/
|       |-- hardware-configuration.nix
|       |-- disko.nix   (optional; you write this)
|       `-- default.nix (or ./web-1 evaluated as a directory)
|-- secrets/            encrypted per-host secret files
|   `-- web-1.yaml
`-- flake.lock
```

Files you edit by hand: `flake.nix`, `hosts.nix`, `hosts/<name>/*`.
Files ops tooling edits: `.sops.yaml` (`install-host`),
`secrets/<name>.yaml` (`update-secrets`), `flake.lock`
(`nix flake update`).

## `flake.nix`

The whole entry point. Post-scaffold, it looks like:

```nix
{
  description = "my-fleet";

  inputs = {
    nixops.url = "github:reflection-dev/nixops";

    nixpkgs.follows   = "nixops/nixpkgs";
    sops-nix.follows  = "nixops/sops-nix";
    deploy-rs.follows = "nixops/deploy-rs";
  };

  outputs = { self, nixops, nixpkgs, deploy-rs, ... }: let
    system = "x86_64-linux";
    hosts  = import ./hosts.nix;

    sshKeys = [
      "ssh-ed25519 AAAA... you@laptop"
    ];
  in {
    nixosConfigurations = nixops.lib.mkNixosConfigs { inherit hosts sshKeys; };
    deploy.nodes        = nixops.lib.mkDeploy self.nixosConfigurations;
    checks.${system}    = deploy-rs.lib.${system}.deployChecks self.deploy;

    devShells.${system}.default = nixops.lib.mkDevShell {
      inherit hosts system;
    };
  };
}
```

What each piece is for:

- **`inputs`**. One dependency: this `nixops` repo. Everything
  else (`nixpkgs`, `sops-nix`, `deploy-rs`) is re-exported by
  nixops and *follows* -- meaning the whole fleet only pins one
  set of versions, controlled from `nixops`. `nix flake update`
  bumps them all.
- **`system = "x86_64-linux"`**. The architecture the fleet
  targets. For a mixed x86/arm64 fleet, override per-host with
  `system = "aarch64-linux"` in the inventory entry.
- **`hosts = import ./hosts.nix`**. The whole inventory read as
  Nix data.
- **`sshKeys`**. The list of admin SSH pubkeys. This is the
  authoritative source for root's `authorized_keys` on every host.
  Add a colleague by appending to the list and running `deploy`.
- **`nixosConfigurations = mkNixosConfigs { hosts; sshKeys; }`**.
  [NixOS and the module system](../foundations/nixos-and-modules.md)'s `nixosSystem` factory, applied to each inventory
  entry. Produces one config per host, all sharing the same base
  modules ([NixOS and the module system](../foundations/nixos-and-modules.md)) plus their per-host modules.
- **`deploy.nodes = mkDeploy self.nixosConfigurations`**.
  [Deploying with deploy-rs](deploy-rs.md)'s factory. Turns each `nixosConfig` into a deploy-rs
  node.
- **`checks.${system}`**. [Deploying with deploy-rs](deploy-rs.md)'s `deployChecks`. Runs on `nix
  flake check` / CI to catch broken deploys before they touch a
  target.
- **`devShells.${system}.default`**. [Your first fleet](your-first-fleet.md)'s devShell -- what
  you get with `nix develop`.

**When to edit:**

- add or remove an admin SSH pubkey -> edit `sshKeys`;
- add a shared module across every host -> extend
  `nixosModules.default` in nixops itself, or wrap `mkNixosConfigs`
  with your own `modules` extras;
- change nixpkgs / sops-nix / deploy-rs version -> `nix flake
  update`, commit the new `flake.lock`.

## `hosts.nix`

Plain data. Every top-level key is a hostname.

```nix
{
  web-1 = {
    ip      = "1.2.3.4";
    modules = [ ./hosts/web-1 ];
  };

  db-1 = {
    ip      = "5.6.7.8";
    system  = "aarch64-linux";                     # optional per-host
    modules = [ ./hosts/db-1 ];
    nixops.firewall.allowedTCPPorts = [ 5432 ];    # inline module fragment
    nixops.nixDefaults.timeZone     = "Europe/Berlin";
  };
}
```

Every entry can carry:

- `ip` (required) -- string, becomes `nixops.host.ip`.
- `system` (optional; default `x86_64-linux`) -- string.
- `modules` (optional; default `[]`) -- list of NixOS module
  paths, evaluated in addition to the shared base modules.
- **any other attribute** -- passed straight to the module system
  as an inline module fragment. That is how the db-1 example above
  sets `nixops.firewall.*` and `nixops.nixDefaults.*` from data.

Reference `lib/mkNixosConfigs.nix` if you want to see the exact
transformation: it removes `system`/`modules`/`ip`, wraps the rest
as an inline module, and adds `networking.hostName = name;`.

**When to edit:**

- add a host -> use `add-host <name>` (writes here for you);
- move a host to a different IP -> change `ip`;
- flip a nixops option for one host -> add the option inline in
  its entry.

## `.sops.yaml`

The scaffold only has your admin recipient:

```yaml
keys:
  - &admin_you   age1youdefinitely...

creation_rules: []
```

After you `install-host web-1`, it grows:

```yaml
keys:
  - &admin_you   age1youdefinitely...
  - &web-1       age1web1derivedfromitssshkey...

creation_rules:
  - path_regex: secrets/web-1\.yaml$
    key_groups:
      - age: [ *admin_you, *web-1 ]
```

[Secrets with sops-nix](sops-nix.md) covers this in detail; this chapter is just naming which
file it is.

**When to edit by hand:**

- add another admin -> append a new `&admin_...` line, then
  `sops updatekeys secrets/*.yaml`;
- remove an admin -> delete the line, then
  `sops updatekeys secrets/*.yaml` (which will re-encrypt without
  the removed recipient);
- change a per-host recipient (rare) -> edit and `sops updatekeys
  secrets/<host>.yaml`.

Do not delete lines automatically written by `install-host` (host
anchors, path_regex rules) unless you know what you are doing.

## `.gitignore`

```text
result
result-*
.direnv/
secrets/*/
```

- `result`, `result-*` -- symlinks Nix drops in the CWD when you
  run `nix build`. Not source; do not commit.
- `.direnv/` -- if you use `direnv` with `nix-direnv`, it caches
  the devShell here.
- `secrets/*/` -- ignore **directories** under `secrets/`. The
  encrypted per-host files (`secrets/web-1.yaml`) are files at the
  top level of `secrets/` and are committed. But `install-host`
  temporarily stashes generated host keys in `secrets/<name>/`;
  those directories must never be committed. The trailing `/` in
  the pattern makes the ignore rule directory-only.

## `README.md`

Boilerplate from the wizard, one page. Refresh it whenever your
fleet grows a habit that is not obvious from the file layout.

## `flake.lock`

Auto-generated. Commit it. [Flakes](../foundations/flakes.md) covers what it is; you never
edit it by hand.

## `hosts/<name>/`

Where per-host NixOS modules live. The inventory entry points at
the directory (`modules = [ ./hosts/web-1 ]`), and the module
system evaluates `hosts/web-1/default.nix` if present, or the
directory as a module (Nix treats a directory as a module when it
contains `default.nix`).

Typical contents:

- **`hardware-configuration.nix`** -- generated during install (by
  `nixos-generate-config` on the target). `nixos-anywhere` prints
  it after a successful install; you copy it in and commit.
- **`disko.nix`** (optional; [Writing host-specific modules](../operating/writing-host-modules.md)) -- your disk layout.
- **`default.nix`** -- the host's own module. Imports the two
  above; sets host-specific services and options.

Example `hosts/web-1/default.nix`:

```nix
{ config, pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
  ];

  services.nginx.enable = true;
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
```

You do not have to write `default.nix` right away. The wizard leaves
a stub `hardware-configuration.nix`; if that is all
`hosts/<name>/` contains, the module system loads it and the host
gets only the base configuration. Add services incrementally.

## `secrets/<name>.yaml`

Encrypted (see [Secrets with sops-nix](sops-nix.md)). One per host that declares
`sops.secrets.*`. Edit through `sops secrets/<name>.yaml` (drops
you into `$EDITOR`) or with the `update-secrets` script.

## Files this repo does NOT scaffold

Deliberately absent:

- **No global `admins.nix` / `roles.nix`**. Admin SSH keys are one
  list in `flake.nix`. Grow it into a proper submodule (email,
  editor, roles, ...) only if you actually need per-admin
  variance. Ship the smaller shape first.
- **No `services/`**. Every host wires up its own services in
  `hosts/<name>/`. If two hosts share a big block, extract to a
  file under `modules/` and import from both -- but do that when
  you have the repetition, not before.
- **No CI config**. Add whatever your team uses (GitHub Actions,
  Forgejo actions, Woodpecker). A useful bare-minimum job is `nix
  flake check` -- it will catch a broken flake before deploy.
- **No `.envrc`**. Direnv is great but personal; add one yourself
  if you like.

## When your fleet grows past this shape

The scaffold is intentionally the smallest thing that works. If
you find yourself:

- **Wishing for per-admin data** (emails, PGP keys, editor
  preferences), promote `sshKeys` to `admins.nix` with a
  submodule and derive `sshKeys` from it.
- **Wishing for environment split** (staging vs. prod), split
  `hosts.nix` into `hosts/staging.nix` and `hosts/prod.nix` and
  choose based on a flake output or an env variable.
- **Wishing for a shared "web tier" role**, extract common services
  into `roles/web.nix` and add to each host's `modules = [
  ./hosts/X ../roles/web.nix ];`.

These are conventions; the toolchain does not care about your
naming.

## What next

You know every file. Next chapter is the daily loop -- rotating
keys, adding admins, splitting a deploy, diagnosing a failed one.

Next: [Day-two operations](../operating/day-two-operations.md)

## References for this chapter

- [Zero to Nix -- Nix language](https://zero-to-nix.com/concepts/nix-language)
  -- worth re-reading now that you have a real repo to hold in
  mind.
- [NixOS Manual -- module structure](https://nixos.org/manual/nixos/stable/#sec-writing-modules)
- [nix.dev -- best practices](https://nix.dev/guides/best-practices)
- [NixOS Wiki -- Flake best practices](https://wiki.nixos.org/wiki/Flakes#Best_practices)
