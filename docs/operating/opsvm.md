---
title: "Operating from an ephemeral workstation VM"
time: "10 minutes"
---
# Operating from an ephemeral workstation VM

> **Prerequisite:** [Install Nix and enable flakes](../foundations/install-nix.md).
>
> **Outcome:** you can spin up a throwaway NixOS workstation with the full ops toolchain via one `nix run`; you know where its state lives on the host, how to isolate several fleets side-by-side, and when this is the right way to work.

Day-to-day fleet ops does not require you to install `sops`, `age`,
`ssh-to-age`, `gum`, `deploy-rs`, `nixos-anywhere`, and a chosen
`nix` on your daily-driver machine. `nixops` ships a NixOS VM that
comes pre-loaded with all of the above and boots in one command.

There are three reasons to reach for it instead of a native install:

- **Isolation from your real keys.** The VM never sees your
  `~/.ssh` or `~/.config/sops/age`. Fleet ssh and age keys generated
  inside are stored in a dedicated host directory that is trivial
  to point elsewhere or wipe.
- **Reproducibility.** Every start builds the workstation from the
  same flake pin; there is no drift between what one operator has
  installed and what the next one has.
- **Shared / borrowed machines.** You can drive a fleet from a
  colleague's laptop or a jump host without leaving a persistent
  toolchain footprint.

If your ops box is your own long-lived laptop that already runs
NixOS or has Nix installed, a plain `nix develop` inside the fleet
repo is still the shorter path. This chapter is about the other
cases.

## Boot it

```console
$ nix run github:reflection-dev/nixops#opsvm
```

That downloads the flake (or hits the cache), builds a small NixOS
system, and launches QEMU with the serial console attached to your
terminal. You will land at the `ops@opsvm` shell, autologged in.

Exit QEMU any time with `Ctrl+A`, then `x`.

The host needs `/dev/kvm` and around 4 GB of free RAM (the VM
defaults to 4 GB / 4 vCPU / 20 GB disk). QEMU itself is bundled
through Nix -- you do not need to install it separately.

## Naming and multiple workstations

`opsvm` is a name. Pass a different one either as the first
positional argument or via the `OPSVM_NAME` env var:

```console
$ nix run github:reflection-dev/nixops#opsvm -- my-fleet
$ OPSVM_NAME=my-fleet nix run github:reflection-dev/nixops#opsvm
```

The name becomes the guest hostname (`ops@my-fleet` prompt) and the
slug for the state directory on the host. Every distinct name gets
its own disk and its own keys, so you can keep multiple isolated
control planes side-by-side and switch between them by changing one
argument.

Positional wins over env; anything after the name is forwarded to
QEMU (for example `-- my-fleet -m 8G`).

## Where state lives

The launcher creates and reuses a directory under
`${XDG_STATE_HOME:-~/.local/state}/nixops-opsvm/<name>/`:

```
<state>/
|-- opsvm.qcow2   persistent VM disk
|-- ssh/          mounted into guest at /home/ops/.ssh
`-- sops-age/     mounted into guest at /home/ops/.config/sops/age
```

Everything the `ops` user writes to `~/.ssh` or `~/.config/sops/age`
lands in one of the two subdirectories on the host, via `virtio-9p`.
`Ctrl+A x`-ing the VM does not lose those files; the next boot
sees them exactly as you left them.

The qcow2 holds anything else that matters for a rebuild -- git
clones, per-shell state, and so on. Trash the entire state dir to
reset a workstation from scratch:

```console
$ rm -rf ~/.local/state/nixops-opsvm/my-fleet
```

Nothing outside that path is touched.

## What is inside

The VM runs [`nixops.nixosModules.opsWorkstation`](../../modules/ops-workstation.nix) on top of the standard
NixOS `qemu-vm.nix` boilerplate. Notable choices:

- **Unprivileged `ops` user** (uid 1000, in `wheel`, passwordless
  `sudo`, autologin on serial). Root has no password, exists for
  rescue only.
- **No inbound sshd.** The workstation only initiates outbound
  ssh; there is no port forward or listening service. You interact
  through the serial console.
- **Ops toolchain on PATH:** `git`, `jq`, `curl`, `vim`, `tmux`,
  `less`, `openssh` (client), `sops`, `age`, `ssh-to-age`, `gum`,
  `nixos-anywhere`, `deploy-rs`.
- **Flakes and the standard substituters** (nixos.org cache +
  nix-community) enabled out of the box.
- **Hostname override via QEMU `fw_cfg`.** The launcher sets
  `opt/opsvm/hostname`; a sysinit-time systemd oneshot inside the
  VM applies it before getty prints the login banner.

## First-boot: generate your fleet identity

The workstation deliberately has no operator keys pre-baked. From
inside the VM, generate a fresh ssh key and age key:

```console
$ ssh-keygen -t ed25519 -C opsvm -f ~/.ssh/id_ed25519 -N ""
$ age-keygen -o ~/.config/sops/age/keys.txt
```

Both land on the host via 9p and persist for the lifetime of the
state directory. The ssh pubkey (`~/.ssh/id_ed25519.pub`) and the
age recipient (`age-keygen -y ~/.config/sops/age/keys.txt`) are what
the [`new`](../deploying/your-first-fleet.md) wizard prompts for.

## From here

You now have exactly the same environment the rest of this manual
assumes:

```console
$ nix run github:reflection-dev/nixops -- new my-fleet
$ cd my-fleet
$ nix develop
```

From this point on, [Day-two operations](day-two-operations.md)
and [Writing host-specific modules](writing-host-modules.md) apply
verbatim -- the fact that the shell you are typing into happens to
be inside a QEMU VM is invisible to every command downstream.
