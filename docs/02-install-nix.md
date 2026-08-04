# 02 -- Install Nix and enable flakes

> Prerequisite: [Chapter 1](01-what-is-nix.md).
> Time: 15 minutes.
> Outcome: `nix run nixpkgs#hello` prints "Hello, world!" from your
> shell, on any Linux, macOS, or WSL2 workstation.

## Which installer

There are two installers in active use in 2026:

- **Determinate Nix Installer** (recommended for this tutorial).
  Reliable uninstall path, enables flakes by default, works
  identically on Linux, macOS, and WSL2. Maintained by Determinate
  Systems. Source: [github.com/DeterminateSystems/nix-installer](https://github.com/DeterminateSystems/nix-installer).
- **Official NixOS installer**. The upstream one. Works fine, but
  the uninstall on macOS is fragile and flakes are opt-in behind an
  extra config file. Source: [nixos.org/download](https://nixos.org/download.html).

Both give you the same `nix` binary once installed. If you already
run NixOS on your workstation, Nix is already there and you can skip
to the "enable flakes" section below.

## Install (Determinate)

```
$ curl --proto '=https' --tlsv1.2 -sSf -L \
    https://install.determinate.systems/nix | sh -s -- install
```

The installer will:

1. ask before touching anything;
2. create a `/nix` directory on the root filesystem;
3. create a `nixbld` group and a set of `nixbld1..nixbldN` users
   used as build sandboxes;
4. install a `nix-daemon` systemd (or launchd on macOS) service;
5. drop a `~/.bash_profile` / `~/.zshenv` snippet so `nix` is on
   your `PATH` in future shells.

Open a new shell, then check:

```
$ nix --version
nix (Determinate Nix) 2.24.10
```

Any version >= 2.18 works for this tutorial.

**Uninstall** (if you ever need to): `/nix/nix-installer uninstall`.

## Install (official upstream)

If you cannot or will not use the Determinate installer:

```
$ sh <(curl -L https://nixos.org/nix/install) --daemon
```

Then, because upstream does not enable flakes by default, create
`~/.config/nix/nix.conf` with:

```
experimental-features = nix-command flakes
```

The Determinate installer sets this for you.

Reference: [nix.dev -- installation](https://nix.dev/install-nix).

## Single-user vs. multi-user

You will read older docs mentioning "single-user" (Nix installed
into a user's home, no daemon) and "multi-user" (system-wide `/nix`,
daemon-owned). **Use multi-user.** Both installers above give you a
multi-user install by default. Single-user only exists for
constrained environments; you will not hit them.

## Enable flakes if not already

Flakes are still labelled "experimental" upstream but are used by
every serious NixOS project today, including this one. Check:

```
$ cat ~/.config/nix/nix.conf 2>/dev/null | grep experimental
experimental-features = nix-command flakes
```

If the line is missing, add it. On multi-user installs you can also
set it system-wide in `/etc/nix/nix.conf`; the Determinate installer
puts it there.

## Sanity check: run a package

```
$ nix run nixpkgs#hello
Hello, world!
```

What just happened:

- `nix run` is the modern subcommand for "fetch, build if needed,
  and execute" a flake output.
- `nixpkgs#hello` is a flake reference: the flake registered under
  the short name `nixpkgs` (there is a default registry mapping it
  to `github:NixOS/nixpkgs`), and inside it, the `hello` output.
- Nix fetched Nixpkgs' `hello` package into `/nix/store/...`, wired
  its `PATH` up, and ran `hello`.

Second time you run it, it is instant -- the store already has it.

## Try a dev shell

```
$ nix shell nixpkgs#jq nixpkgs#curl
```

You are now in a shell where `jq` and `curl` are on `PATH`, without
touching your system installation. Exit with `exit`. Nothing was
persisted on disk beyond the store copies.

## Try running this repo's wizard (dry run)

You do not have to actually make a fleet yet -- we do that in
Chapter 9. But you can prove the moving parts are wired:

```
$ nix run github:reflection-dev/nixops -- --help
```

The first invocation will download a lot (nixpkgs alone is a few
hundred MB of cached artefacts). Subsequent runs are fast because
they hit the store.

## Common gotchas

- **`error: experimental Nix feature 'nix-command' is disabled`**
  -- the `experimental-features` line in `nix.conf` is missing or
  the file is in the wrong place. Fix and re-run.
- **`error: git tree ... is dirty`** -- you tried to build from a
  local path that has uncommitted changes. Chapter 4 covers this.
- **`/nix` on a mounted volume is slow** -- that is a filesystem
  problem, not a Nix problem. Move `/nix` to a fast local disk.
- **macOS + Apple silicon + Rosetta confusion** -- if you see
  "unsupported system", check `nix show-config | grep system`; it
  should be `aarch64-darwin`, not `x86_64-darwin`. If it is wrong,
  reinstall on an arm64 shell.

## Cachix: skip the compile

Nix can pull pre-built store paths from a binary cache, saving hours
of local compilation. The public cache `cache.nixos.org` is enabled
by default. Community caches like `nix-community.cachix.org` (which
this repo uses for `deploy-rs`) speed things further; the repo's
`flake.nix` declares them and Nix will offer to trust them the first
time.

More: [nix.dev -- binary caches](https://nix.dev/manual/nix/stable/command-ref/conf-file.html#conf-substituters).

## What you have now

- A working `nix` command on your workstation.
- Flakes enabled.
- A binary cache configured.
- The vocabulary to say "I want to run flake output X" without hand-
  waving.

Next: the language itself. You cannot read `flake.nix` or `hosts.nix`
without knowing what an attribute set is, so we do that before
touching flakes.

Next: [Chapter 3 -- The Nix language.](03-nix-language.md)

## References for this chapter

- [nix.dev -- installation](https://nix.dev/install-nix)
- [Determinate Nix Installer README](https://github.com/DeterminateSystems/nix-installer)
- [Nix Reference Manual -- CLI](https://nix.dev/manual/nix/stable/command-ref/new-cli/nix)
- [Nixpkgs website](https://search.nixos.org/packages) -- search for
  any package by name; the URL shows you its attribute path in
  Nixpkgs.
