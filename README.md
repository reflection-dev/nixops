<div align="center">

# nixops

_Your servers, as code. Reproducible, rollback-safe, rebuildable by any teammate._

<a href="https://github.com/reflection-dev/nixops/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/reflection-dev/nixops/actions/workflows/ci.yml/badge.svg"></a>
<a href="https://nixos.org"><img alt="Nix flake" src="https://img.shields.io/badge/Nix-flake-5277C3?logo=nixos&amp;logoColor=white"></a>
<a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-7aa2f7"></a>

<!-- HERO_GIF: recorded terminal demo lands in the next commit (see docs/operating/opsvm.md) -->

</div>

Built on [NixOS](https://nixos.org). A single repo describes your set of
servers as plain data -- hostnames, secrets, disks, and per-host
configuration. Interactive wizards add hosts, provision secrets, install
NixOS on any SSH-reachable Linux, and roll fleet-wide updates out with
automatic rollback -- plus an ephemeral operator VM you can throw away.

> **New to NixOS?** The [zero-to-fleet tutorial](docs/overview/index.md) starts
> from "what even is this" and ends with you running a real fleet -- no prior
> functional-programming or DevOps background required.

## Contents

- [Quick start](#quick-start)
- [Ephemeral operator VM](#ephemeral-operator-vm)
- [Instance repo layout](#instance-repo-layout)
- [devShell commands](#devshell-commands)
- [Flake outputs](#flake-outputs)
- [Base modules](#base-modules)
- [Bootstrap flow](#bootstrap-flow)
- [New to Nix?](#new-to-nix)
- [Non-goals](#non-goals)
- [Contributing](#contributing)
- [License](#license)

## Quick start

Requires [Nix](https://nixos.org/download.html) with flakes enabled.

```
nix run github:reflection-dev/nixops -- new my-fleet
cd my-fleet
nix develop
```

The wizard prompts for description, SSH keys (auto-detected from
`~/.ssh/*.pub`), age recipient (auto-detected from
`~/.config/sops/age/keys.txt`), optionally `git init`s the repo, and
optionally scaffolds a first host through `add-host`.

Bare-bones alternative for those who prefer to edit placeholders by hand:

```
nix flake init -t github:reflection-dev/nixops
```

## Ephemeral operator VM

For dry-runs, demos, or driving a fleet from a machine you do not want to mix
with your real `~/.ssh` / `~/.config/sops/age`, boot a throwaway NixOS
workstation:

```
nix run github:reflection-dev/nixops#opsvm
```

Optional name (becomes the guest hostname and the state-dir slug):

```
nix run github:reflection-dev/nixops#opsvm -- my-fleet
# equivalently: OPSVM_NAME=my-fleet nix run github:reflection-dev/nixops#opsvm
```

State lives on the host under `${XDG_STATE_HOME:-~/.local/state}/nixops-opsvm/<name>/`:

```
<state>/
|-- opsvm.qcow2   persistent VM disk (rm to reset)
|-- ssh/          mounted into guest at /home/ops/.ssh
`-- sops-age/     mounted into guest at /home/ops/.config/sops/age
```

Notes:

- QEMU is bundled through Nix; the host only needs `/dev/kvm`.
- Serial console autologins as `ops` (unprivileged, passwordless sudo).
  Exit QEMU with `Ctrl+A`, then `x`.
- Different names get separate state dirs and disks -- juggle several
  isolated workstations from one command.
- No inbound sshd; the VM initiates outbound ssh only (`nixos-anywhere`,
  `install-host`, ...).

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

Shared SSH keys live inline in `flake.nix` (one list, every host). Per-host
NixOS modules live under `hosts/<name>/` and are pulled in via the
`modules = [ ./hosts/<name> ];` field on the inventory entry.

## devShell commands

`nix develop` on the instance repo hands the operator:

| command                 | what it does                                                           |
| ----------------------- | ---------------------------------------------------------------------- |
| `ssh <name>`            | ssh via a config generated from the inventory (`Host <name> ...`)      |
| `add-host <name>`       | prompts for IP, scaffolds `hosts/<name>/`, appends to `hosts.nix`      |
| `install-host <name>`   | `nixos-anywhere` + sops recipient inject + interactive secret prompts  |
| `update-secrets [name]` | interactively fill any `sops.secrets.*` not yet set                    |
| `deploy [name]`         | `deploy-rs` wrapper: all nodes, or one by name                         |

Plus in `PATH`: `sops`, `age`, `ssh-to-age`, `deploy-rs`, `nixos-anywhere`,
`jq`, `gum`. All interactive prompts use `gum` -- no plain `read` UX.

## Flake outputs

```
nixops.nixosModules.default          # aggregator: sops-nix + all base modules
nixops.nixosModules.{ssh, sops, users, nix-defaults, firewall}
nixops.nixosModules.opsWorkstation   # ops user + toolchain (opt-in, workstation role)
nixops.lib.mkNixosConfigs { hosts; sshKeys; }
nixops.lib.mkDeploy nixosConfigurations
nixops.lib.mkDevShell { hosts; system; extraPackages? }
nixops.templates.default             # for `nix flake init -t`
nixops.packages.<system>.opsvm       # nixos-vm: opsWorkstation + qemu-vm.nix
nixops.apps.<system>.{new, default}  # the wizard
nixops.apps.<system>.opsvm           # ephemeral workstation launcher
```

## Base modules

Every module is toggle-driven (`nixops.<name>.enable`, default true for the
sane cases). Any host can opt out of any individual piece.

| module         | purpose                                                                                       |
| -------------- | --------------------------------------------------------------------------------------------- |
| `nix-defaults` | flakes, weekly GC (30d retention), UTC, UTF-8 locale, `system.stateVersion`, base CLI toolbox |
| `ssh`          | hardened sshd; root allowed by key only, no passwords, no keyboard-interactive                |
| `sops`         | `sops.age.sshKeyPaths = [ /etc/ssh/ssh_host_ed25519_key ]`                                    |
| `users`        | seeds root's authorized_keys from the shared `sshKeys` list                                   |
| `firewall`     | allowlist mode; extra ports via `nixops.firewall.allowedTCP/UDPPorts`                         |

## Bootstrap flow

1. Have an age key at `~/.config/sops/age/keys.txt` (or let the wizard
   generate one) -- its recipient goes into `.sops.yaml` as `&admin_<name>`.
2. `add-host <name>` scaffolds a host entry.
3. `install-host <name>` runs `nixos-anywhere`:
   - generates the target's `ssh_host_ed25519_key` locally,
   - derives its age recipient (`ssh-to-age`),
   - appends `&<name>` to `.sops.yaml` + a `creation_rule` for
     `secrets/<name>.yaml`,
   - prompts for any missing `sops.secrets.*`,
   - kexecs NixOS with the host key as `--extra-files`,
   - removes the local copy of the private key on success.
4. Subsequent updates: `deploy <name>` (or `deploy` for the whole fleet).

## New to Nix?

The [zero-to-fleet tutorial](docs/overview/index.md) under [`docs/`](docs/)
is written for ops folks who have never touched Nix, NixOS, or flakes. It
covers the language, the module system, `sops-nix`, `nixos-anywhere`, and
`deploy-rs`, ending with a walkthrough of installing and operating a real
fleet with this repo. Every chapter links to the canonical Nix docs
(nix.dev, NixOS Manual, Zero to Nix, NixOS Wiki, Discourse) for deeper
dives.

## Non-goals

- **AI-specific tooling** (agents, coding assistants, model hosts) -- that
  layer lives in [reflection-dev/castle](https://github.com/reflection-dev/castle),
  which will build on top of `nixops`.
- **Hardware/disko recipes.** Every fleet's storage story is different;
  `nixops` does not ship parameterised disk layouts. Instances drop their
  own `hosts/<name>/disko.nix` next to `hardware-configuration.nix`.
- **Managed service modules** (Postgres, Redis, ...). Add these in the
  instance or in a purpose-specific library on top.
- **Multi-cloud abstractions.** `install-host` works over any SSH target
  reachable by `nixos-anywhere`; provider-specific modules can land later
  as opt-in extras.

## Contributing

Issues and PRs welcome -- see [CONTRIBUTING.md](CONTRIBUTING.md) for the
development setup, the module/script conventions, and the PR checklist.
Be kind ([Code of Conduct](CODE_OF_CONDUCT.md)); report vulnerabilities
privately per [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) (c) 2026 Andy Smith.
