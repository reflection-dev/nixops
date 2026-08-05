---
title: "What Nix is and why it matters"
time: "20 minutes of reading"
---
# What Nix is and why it matters

> **Prerequisite:** none.
>
> **Outcome:** a working mental model of Nix, NixOS, and where `nixops` fits.

You do not need to touch a keyboard for this chapter. It exists so
that when [The Nix language](nix-language.md) tells you to write `{ pkgs, ... }: { ... }`, you
know why.

## The one-paragraph pitch

**Nix** is a package manager and build system that treats every
package as the deterministic output of a pure function of its inputs.
Change any input -- compiler version, source hash, a flag -- and you
get a different, differently-named output. Nothing is installed in
`/usr/bin`; everything lives at a content-addressed path in
`/nix/store/<hash>-<name>/`. Because the input-to-output relationship
is total and pure, two people on two continents starting from the
same expression produce byte-identical results, and any two versions
of a package can coexist on the same machine without conflict.

**NixOS** is a Linux distribution where *the entire operating system*
-- kernel version, systemd units, users, `/etc/*`, the whole thing --
is one giant expression evaluated by Nix. The running system is a
symlink into the store; switching configurations is atomic; rolling
back is one command.

**nixops** (this repo) is a small opinionated toolkit that turns a
plain-data inventory of hosts (`hosts.nix`) plus a shared set of
NixOS modules into a fleet: a single place to add a machine, install
it remotely, ship secrets, and roll out changes with automatic
safety.

## Why an ops person should care

If the ops tools you have used are apt/dnf, Ansible, Terraform,
Puppet, Chef, or Docker, you have hit at least some of these:

- **Snowflake servers.** Machine A has Nginx 1.18 because it was
  installed in 2022; machine B has 1.22 because it was rebuilt last
  year. Nobody knows which packages have been apt-get-installed
  interactively.
- **"Works on my machine"** because someone's dev laptop has a
  different `libssl`, `python3`, or `docker` version than production.
- **Configuration drift.** Ansible runs are supposed to be
  idempotent, but a task fails halfway, or someone SSHs in and edits
  a config, and now the declared state and the actual state disagree.
- **Rollbacks are terrifying.** "Deploy" means "run a bunch of
  commands"; "rollback" means "run them again in the other
  direction" -- if you remember which ones.
- **Secrets sprawl.** Some in Vault, some in `.env` files, some in
  Ansible-vault, some in a wiki page. Adding a new admin means
  finding all the places and re-encrypting.

Nix addresses these in a specific way:

- **A machine is a value.** A NixOS host is the output of
  `nixos-rebuild`-ing an expression. Two hosts built from the same
  expression are byte-for-byte the same OS (modulo /var content).
  There is no such thing as "the running system diverged from the
  config": the running system *is* the current generation of the
  config.
- **Every generation is preserved.** Every previous build stays in
  the Nix store; the boot loader lists them; rolling back is one
  reboot away.
- **All dependencies are captured.** The Nginx version is not
  "whatever `apt-get` picked up today", it is pinned to a specific
  nixpkgs commit in your `flake.lock`. Deploys are reproducible;
  bisecting a regression means changing one hash.
- **Secrets have first-class module support.** `sops-nix` lets you
  commit encrypted secrets to git, decrypt them on-host with a key
  that never leaves the host, and reference them from any NixOS
  module ([Secrets with sops-nix](../deploying/sops-nix.md)).
- **Deploys are atomic and reversible.** `deploy-rs` runs your new
  configuration, pings your workstation from the target after
  activation, and if the ping does not come back it automatically
  rolls back to the previous generation ([Deploying with deploy-rs](../deploying/deploy-rs.md)).

## Where Nix fits vs. what you know

The comparisons below are lossy on purpose; they get you oriented,
not certified.

### vs. apt / dnf / brew

Traditional package managers install into shared directories
(`/usr/bin`, `/usr/lib`). Two versions of the same package conflict;
"install everything on the box" is a single ambient environment.

Nix installs each package into its own store path
(`/nix/store/xyz-nginx-1.24.0/`) and symlinks a *profile* into your
`PATH`. Two versions coexist trivially; you can build a shell where
Python 3.11 is on `PATH` for one project and 3.12 for another with no
ceremony. On NixOS, `/etc/nginx/nginx.conf` is a symlink into the
store; if you edit it, `nixos-rebuild` will overwrite the edit on the
next switch, because the config is generated from the module.

### vs. Ansible / Salt / Puppet / Chef

Config-management tools are **imperative** or **eventually
consistent**: you describe steps ("install package X; render template
Y; restart service Z"), and the tool tries to reach the target
state. Success or failure is per-task, and drift creeps in because
"the target state" is what the last run of the tool did, not what
the file system currently contains.

Nix + NixOS is **declarative and constructive**. You describe the
target: `services.nginx.enable = true; networking.hostName = "web-1";`.
The tool computes a whole new system generation, activates it
atomically, and if activation fails, you are still on the old one.
There is no per-task "did it succeed"; there is one "is the whole new
system live yet" boolean.

Ansible playbooks are collections of tasks executed against a target.
NixOS modules are collections of options merged into a whole-system
value that is then realised. If two modules set the same option, the
module system tells you at evaluation time, not at 3am when the two
templates trip over each other on disk.

### vs. Terraform

Terraform is the closest cultural cousin. Both are declarative, both
have state, both talk about diffs and plans. Two differences:

- Terraform manages *external* resources (cloud instances, DNS,
  networks) through provider APIs. NixOS manages the *inside* of a
  Linux host. They complement each other: you can Terraform up VMs
  and let NixOS + `nixos-anywhere` install them.
- Terraform's state file records what it *believes* the world looks
  like. NixOS's "state" is the current generation symlink; there is
  nothing external to drift from.

### vs. Docker / OCI images

Docker gives you reproducible-ish container images by baking the
build into a `Dockerfile`. Nix gives you reproducible packages by
making the whole language pure; it can build OCI images too
(`pkgs.dockerTools.buildImage`) and, when it does, they are
bit-identical across machines and days.

NixOS is not "Docker for the whole OS", but the mental jump is
similar: instead of `apt-get install` on a running system, you
declare what should be there and let the tool assemble it.

### vs. plain shell scripts + SSH

That is what most fleets start with, and it works fine for one
machine. When you have four, "install a new one" becomes a
long-lived doc; when you have twenty, an operator can no longer hold
"what's different about machine 12" in their head. `nixops` is
essentially "shell scripts + SSH" for the imperative parts
(`add-host`, `install-host`, `deploy`) wrapping a declarative core
(the flake + modules) that tells you exactly what is different about
machine 12.

## The mental model in three words

**Value, not steps.**

Every time you catch yourself thinking "run this command, then that
command, then edit this file", stop. Ask: what is the *value* I want
this machine to hold? Write that down as a module. Let Nix compute
the steps.

## Vocabulary you will meet in the next chapters

You do not need to memorise these. They are here so you can flip
back when a term feels familiar-but-fuzzy.

- **Derivation** -- a build recipe. A Nix expression evaluates down
  to a derivation, which the Nix builder realises into a store path.
- **Store / store path** -- `/nix/store/<hash>-<name>`. Every built
  artefact lives here. `hash` is over all the inputs.
- **Nixpkgs** -- the giant collection of package definitions that
  the community maintains. Think Debian's package archive, but as a
  git repo of Nix expressions.
- **Channel / flake input** -- how you pin which version of nixpkgs
  (or any other Nix repo) you are using. Flakes are the modern
  mechanism; channels are the legacy one. This tutorial uses flakes.
- **Flake** -- a git repository with a `flake.nix` at its root that
  declares its inputs (dependencies) and outputs (what it produces:
  packages, NixOS configs, dev shells, apps).
- **Module** -- a chunk of NixOS configuration. Each module can
  declare `options` (what can be set) and `config` (what to set).
  The module system merges every module into one big system value.
- **Generation** -- a specific historical build of a NixOS system.
  Every `nixos-rebuild switch` (or `deploy`) makes a new generation;
  the previous ones are still on disk.
- **Activation** -- switching the running system to a new generation
  by updating symlinks and reloading systemd.
- **Overlay** -- a way to patch nixpkgs (add a package, change a
  version). You will not need overlays for a while.

## Prerequisites for what comes next

- [Install Nix and enable flakes](install-nix.md) will install Nix on your workstation. That is a one-time
  step that touches your filesystem outside your home directory.
  Read [Install Nix and enable flakes](install-nix.md) in full before running any of its commands.

Ready? [Install Nix and enable flakes](install-nix.md)

## References for this chapter

- [nix.dev -- "What is Nix"](https://nix.dev/tutorials/nix-language)
  -- broader intro from the official docs.
- [Zero to Nix -- "Why Nix"](https://zero-to-nix.com/concepts/why-nix)
  -- Determinate Systems' opinionated intro; short and readable.
- [NixOS website -- learn page](https://nixos.org/learn.html) --
  hub of official and community resources.
- [Eelco Dolstra's PhD thesis, "The Purely Functional Software
  Deployment Model"](https://edolstra.github.io/pubs/phd-thesis.pdf)
  -- the origin. You do not need to read this to use Nix, but if the
  "why" nags you, it is the source.
