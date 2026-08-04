# nixops

Generic NixOS fleet base -- inventory-driven modules, `deploy-rs` and
`sops-nix` wiring, `nixos-anywhere` bootstrap, and an ops devShell with
per-inventory ssh aliases + interactive wizards.

## New to Nix?

There is a full zero-to-fleet tutorial in [`docs/`](docs/00-index.md).
Fourteen chapters, written for ops folks who have never touched Nix,
NixOS, or flakes -- covering the language, the module system,
`sops-nix`, `nixos-anywhere`, and `deploy-rs`, ending with a walkthrough
of installing and operating a real fleet with this repo. Every chapter
links to the canonical Nix docs (nix.dev, NixOS Manual, Zero to Nix,
NixOS Wiki, Discourse) for deeper dives.

Start with [docs/00-index.md](docs/00-index.md).

## Quick start

```
nix run github:reflection-dev/nixops -- new my-fleet
cd my-fleet
nix develop
```

The wizard prompts for description, SSH keys (auto-detected from
`~/.ssh/*.pub`), age recipient (auto-detected from
`~/.config/sops/age/keys.txt`), optionally `git init`s the repo, and
optionally scaffolds a first host through `add-host`.

Bare-bones alternative for those who prefer to edit placeholders by
hand:

```
nix flake init -t github:reflection-dev/nixops
```

## Instance repo layout

Five files -- everything else grows as hosts are added.

```
my-fleet/
|-- flake.nix       inputs + outputs (nixosConfigurations, deploy.nodes, devShell)
|-- hosts.nix       plain-data inventory: { <name> = { ip; modules; ... }; ... }
|-- .sops.yaml      age recipients (admins + per-host)
|-- .gitignore
`-- README.md
```

Shared SSH keys live inline in `flake.nix` (one list, every host).
Per-host NixOS modules live under `hosts/<name>/` and are pulled in
via the `modules = [ ./hosts/<name> ];` field on the inventory entry.

## devShell commands

`nix develop` on the instance repo hands the operator:

| command                 | what it does                                                           |
| ----------------------- | ---------------------------------------------------------------------- |
| `ssh <name>`            | ssh via a config generated from the inventory (`Host <name> ...`)      |
| `add-host <name>`       | prompts for IP, scaffolds `hosts/<name>/`, appends to `hosts.nix`      |
| `install-host <name>`   | `nixos-anywhere` + sops recipient inject + interactive secret prompts  |
| `update-secrets [name]` | interactively fill any `sops.secrets.*` not yet set                    |
| `deploy [name]`         | `deploy-rs` wrapper: all nodes, or one by name                         |

Plus in `PATH`: `sops`, `age`, `ssh-to-age`, `deploy-rs`,
`nixos-anywhere`, `jq`, `gum`. All interactive prompts use `gum` -- no
plain `read` UX.

## Flake outputs

```
nixops.nixosModules.default          # aggregator: sops-nix + all base modules
nixops.nixosModules.{ssh, sops, users, nix-defaults, firewall}
nixops.lib.mkNixosConfigs { hosts; sshKeys; }
nixops.lib.mkDeploy nixosConfigurations
nixops.lib.mkDevShell { hosts; system; extraPackages? }
nixops.templates.default             # for `nix flake init -t`
nixops.apps.<system>.{new, default}  # the wizard
```

## Base modules

Every module is toggle-driven (`nixops.<name>.enable`, default true for
the sane cases). Any host can opt out of any individual piece.

| module         | purpose                                                                        |
| -------------- | ------------------------------------------------------------------------------ |
| `nix-defaults` | flakes, weekly GC (30d retention), UTC, UTF-8 locale, `system.stateVersion`, base CLI toolbox |
| `ssh`          | hardened sshd; root allowed by key only, no passwords, no keyboard-interactive |
| `sops`         | `sops.age.sshKeyPaths = [ /etc/ssh/ssh_host_ed25519_key ]`                     |
| `users`        | seeds root's authorized_keys from the shared `sshKeys` list                    |
| `firewall`     | allowlist mode; extra ports via `nixops.firewall.allowedTCP/UDPPorts`          |

## Bootstrap flow

1. Have an age key at `~/.config/sops/age/keys.txt` (or let the wizard
   generate one) -- its recipient goes into `.sops.yaml` as
   `&admin_<name>`.
2. `add-host <name>` scaffolds a host entry.
3. `install-host <name>` runs `nixos-anywhere`:
   - generates the target's `ssh_host_ed25519_key` locally,
   - derives its age recipient (`ssh-to-age`),
   - appends `&<name>` to `.sops.yaml` + a `creation_rule` for
     `secrets/<name>.yaml`,
   - prompts for any missing `sops.secrets.*`,
   - kexecs NixOS with the host key as `--extra-files`,
   - removes the local copy of the private key on success.
4. Subsequent updates: `deploy <name>` (or `deploy` for the whole
   fleet).

## Non-goals

- **AI-specific tooling** (agents, coding assistants, model hosts) --
  that layer lives in [reflection-dev/castle](https://github.com/reflection-dev/castle),
  which will build on top of `nixops`.
- **Hardware/disko recipes**. Every fleet's storage story is
  different; nixops does not ship parameterised disk layouts. Instances
  drop their own `hosts/<name>/disko.nix` next to
  `hardware-configuration.nix`.
- **Managed service modules** (Postgres, Redis, ...). Add these in the
  instance or in a purpose-specific library on top.
- **Multi-cloud abstractions**. `install-host` works over any SSH
  target reachable by `nixos-anywhere`; provider-specific modules can
  land later as opt-in extras.
