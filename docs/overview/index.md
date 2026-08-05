# nixops -- Nix for Ops: a zero-to-fleet tutorial

This is a guided course for operations engineers who have never touched
Nix, NixOS, or flakes before, but want to actually run a fleet of NixOS
machines with `nixops` at the end of it. It does not assume any prior
functional programming, and it does not pretend that Nix is a small
tool -- but it does insist on a linear reading order so you never hit
a chapter that needs a concept you have not seen yet.

You will finish able to:

- explain what Nix, NixOS, flakes, and modules are, in your own words;
- read (and edit) the `flake.nix` / `hosts.nix` / `.sops.yaml` triple
  that this repo scaffolds;
- install a fresh Linux server from your laptop with one command
  (`install-host`), including its secrets;
- deploy configuration changes across the whole fleet with one command
  (`deploy`), safely, with automatic rollback if the new config breaks;
- know where in the official manuals to go next.

## Who this is for

- **Ops folks who already run servers** with Ansible, Terraform,
  Kubernetes manifests, plain SSH + shell scripts, or whatever else.
  The comparisons in Chapter 1 are aimed at you.
- **First-time Nix users.** No prior functional-programming or
  package-manager exposure is assumed. If you have used Nix before,
  Chapters 1-4 will feel slow; skim them and start at Chapter 5.

## What you need before Chapter 2

- A workstation running Linux, macOS, or WSL2. Nix works on all three;
  NixOS itself only runs on Linux, but you can build and deploy NixOS
  configurations from any workstation Nix supports.
- Root SSH access to at least one Linux target you are willing to
  reinstall (a cheap VPS is fine). Chapters 7 and 9 need this.
- Comfort with a Unix shell, `ssh`, and reading YAML/JSON. You do not
  need to know any functional programming.

## Reading order

The chapters build on each other; skipping ahead will hurt. If you
only have 30 minutes, read Chapters 1, 9, and 11 -- you will not
understand the internals, but you will be able to operate a fleet
someone else set up.

| # | Chapter | Purpose |
| - | ------- | ------- |
| 01 | [What Nix is and why it matters](../foundations/what-is-nix.md) | Mental model + comparisons to apt/Ansible/Docker |
| 02 | [Install Nix and enable flakes](../foundations/install-nix.md) | Get a working Nix on your workstation |
| 03 | [The Nix language](../foundations/nix-language.md) | Just enough to read this repo |
| 04 | [Flakes](../foundations/flakes.md) | Inputs, outputs, lock file, the `nix` CLI |
| 05 | [NixOS and the module system](../foundations/nixos-and-modules.md) | Declarative machines; options and config |
| 06 | [Secrets with sops-nix](../deploying/sops-nix.md) | age keys, `.sops.yaml`, `sops.secrets.*` |
| 07 | [Remote install with nixos-anywhere](../deploying/nixos-anywhere.md) | Install NixOS on any Linux target |
| 08 | [Deploying with deploy-rs](../deploying/deploy-rs.md) | Activation, rollback, checks |
| 09 | [Your first fleet](../deploying/your-first-fleet.md) | End-to-end walkthrough |
| 10 | [Anatomy of an instance repo](../deploying/anatomy-of-an-instance.md) | Every file the wizard produces |
| 11 | [Day-two operations](../operating/day-two-operations.md) | The routine ops loop |
| 12 | [Writing host-specific modules](../operating/writing-host-modules.md) | Adding services, disks, firewall holes |
| 13 | [Troubleshooting](../operating/troubleshooting.md) | Failure modes and how to diagnose |
| 14 | [Further reading](../operating/further-reading.md) | Curated links into the official docs |

## Conventions

- **ASCII only.** No em-dashes, curly quotes, or ellipses. `--` means
  literally two hyphens. Copy-paste-friendly.
- **Shell blocks** are prefixed with `$` when they run on your
  workstation and `#` when they run as root on a target host. Blocks
  without a prefix are file contents.
- **Links** into official docs are named inline. When a chapter refers
  to a canonical manual (Nix Reference, NixOS Manual, Nixpkgs Manual),
  you will find the full URL and section number in the paragraph.
- **This repo's own code** is referenced with file paths relative to
  the nixops repo root, for example `modules/ssh.nix` or
  `lib/mkDevShell.nix`. Open those in a second window while you read.

## The one link you should bookmark now

[nix.dev](https://nix.dev/) -- the official modern documentation
site, maintained by the NixOS Foundation. Every time this tutorial
sends you elsewhere, it is usually there. Bookmark it before starting
Chapter 1.

Ready? [Start with Chapter 1.](../foundations/what-is-nix.md)
