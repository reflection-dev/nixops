---
time: "30 minutes"
---
# Flakes

> **Prerequisite:** [The Nix language](nix-language.md).
>
> **Outcome:** you can read and edit a `flake.nix`; you know how the lock file works; you have used `nix run`, `nix develop`, `nix build`, and `nix flake update`.

A **flake** is a git repository with a `flake.nix` at its root. That
file declares the flake's *inputs* (its dependencies -- other
flakes) and its *outputs* (what this flake produces -- packages,
NixOS configurations, dev shells, apps, and so on). A `flake.lock`
next to it pins every input to a specific commit and hash, so
everyone who builds from the same tree produces the same result.

That is the whole idea. Everything else is convention.

## Why flakes exist

Before flakes, you pulled other Nix code by referring to a channel
name (`<nixpkgs>`), a URL, or an ambient environment variable. It
worked, but you could not tell from the source alone which version
you were pulling. Flakes require you to declare inputs by URL and
lock them, so a repo is a self-contained, byte-reproducible source.

Flakes are still labelled "experimental" upstream, but they are what
NixOS-in-2026 is built on, and every project you will interact with
(including this one) uses them.

## A minimal flake

```nix
{
  description = "example flake";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }: {
    packages.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.hello;
  };
}
```

Two things to notice:

- `inputs.nixpkgs.url = "github:...";` declares a dependency.
- `outputs = { self, nixpkgs }: { ... };` is a function taking
  every input by name (plus `self`, meaning this flake), and
  returning an attribute set of outputs.

When you say `nix build .#default`, Nix:

1. reads `flake.nix`;
2. fetches every input at the revision pinned in `flake.lock`
   (or, if there is no lock file yet, at whatever the URL currently
   points to, and writes `flake.lock`);
3. calls the `outputs` function with those inputs;
4. looks up `packages.<current-system>.default` in the result;
5. builds it.

## Input URLs

Common forms:

- `github:OWNER/REPO` -- latest default branch.
- `github:OWNER/REPO/BRANCH_OR_TAG_OR_COMMIT`.
- `git+https://gitea.example.com/foo/bar`.
- `path:/absolute/path` -- a local checkout. Handy while
  developing something you have not committed yet.
- `tarball+https://example.com/foo.tar.gz`.

The full syntax is documented at [nix.dev -- flake references](https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-flake#url-like-syntax).

### `follows` -- deduping shared inputs

Two of your inputs both depend on `nixpkgs`. Without any help you
end up with three copies (yours and each input's) and their eval
does not agree. The fix is `inputs.X.inputs.Y.follows = "Y"`, which
tells `X` to use *your* `Y`.

This repo's `flake.nix` uses it:

```nix
inputs = {
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  sops-nix = {
    url = "github:Mic92/sops-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  deploy-rs = {
    url = "github:serokell/deploy-rs";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

That means "sops-nix and deploy-rs both use the same nixpkgs I use",
avoiding three-way version skew.

## The lock file

`flake.lock` is JSON. Each input is pinned by its Git commit hash
plus the NAR hash of its contents. `nix flake update` refreshes
every input to their latest URL-resolved revision and updates the
lock. `nix flake lock --update-input X` refreshes just `X`.

You commit `flake.lock`. It is the point of flakes.

Reference: [Nix Reference Manual -- flakes](https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-flake).

## Outputs

There is no strict schema, but the community-standard outputs are:

- `packages.<system>.<name>` -- built packages. `default` is what
  `nix build` picks up with no `.#name` given.
- `apps.<system>.<name>` -- runnable via `nix run`. This repo's
  `apps.<system>.new` is the fleet-scaffolding wizard.
- `devShells.<system>.<name>` -- shells you enter with `nix
  develop`. This repo's instance flake declares one here so
  `nix develop` in a fresh clone drops you into the ops toolbox.
- `nixosConfigurations.<hostname>` -- a NixOS system. In this repo
  the `deploy` command (thin wrapper over `deploy-rs`) reads this
  and rolls it out to `<hostname>`; upstream NixOS's own
  `nixos-rebuild` would read the same output for a local rebuild.
- `nixosModules.<name>` -- reusable NixOS modules that other flakes
  import. This repo exports `nixosModules.default`, which is the
  aggregator of all the base modules.
- `lib.<name>` -- Nix-language helpers. This repo's `lib.mkDevShell`
  and `lib.mkNixosConfigs` are here.
- `templates.<name>` -- source trees to copy with `nix flake init
  -t`. This repo's `templates.default` scaffolds an instance repo.
- `checks.<system>.<name>` -- runnable via `nix flake check`.
  Instance flakes wire `deploy-rs`'s deploy-checks in here.

`<system>` is one of `x86_64-linux`, `aarch64-linux`,
`x86_64-darwin`, `aarch64-darwin`. To publish an output for many
systems you use `nixpkgs.lib.genAttrs [ ... ]`; this repo does that
for `apps`.

Full reference: [Nix Reference Manual -- flake outputs](https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-flake#flake-outputs).

## Reading this repo's `flake.nix`

Open [`flake.nix`](../flake.nix) alongside this section.

```nix
{
  description = "nixops -- generic NixOS fleet base: inventory-driven modules, deploy tooling, ops devShell";

  nixConfig = {
    extra-substituters = [ "https://nix-community.cachix.org" ];
    ...
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
    ...
  };

  outputs = { self, nixpkgs, sops-nix, deploy-rs, ... }: let
    version = self.shortRev or self.dirtyShortRev or "unknown";
  in {
    nixosModules.default = { imports = [ sops-nix.nixosModules.sops ./modules ]; };
    lib = {
      mkNixosConfigs = import ./lib/mkNixosConfigs.nix { ... };
      mkDeploy       = import ./lib/mkDeploy.nix       { ... };
      mkDevShell     = import ./lib/mkDevShell.nix     { ... };
    };
    templates.default = { path = ./templates/default; ... };
    apps = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (system: ...);
  };
}
```

Read piece by piece:

- `description` -- freeform. Shown by `nix flake metadata`.
- `nixConfig` -- extra Nix settings to apply *when this flake is
  loaded*. Here it advertises the `nix-community` cachix as a
  substituter, so people running `nix run github:reflection-dev/nixops`
  can get pre-built `deploy-rs` bits.
- `inputs` -- the three deps: `nixpkgs`, `sops-nix`, `deploy-rs`.
  The latter two follow this flake's `nixpkgs` (see `follows`
  above).
- `outputs = { self, nixpkgs, sops-nix, deploy-rs, ... }: let ...
  in { ... }` -- a function; the `let ... in` computes `version`
  from git metadata and then returns the outputs record.
- `nixosModules.default` -- an aggregator module that imports
  sops-nix's own NixOS module *plus* every module under
  `./modules/`. Consumers get all base functionality in one line:
  `imports = [ nixops.nixosModules.default ];`.
- `lib.mk*` -- the three factory functions exposed for instance
  flakes to call.
- `templates.default` -- points at `templates/default/`, so
  `nix flake init -t github:reflection-dev/nixops` copies that tree
  into the current directory.
- `apps` -- per-system apps generated by `genAttrs`. Both
  `apps.<sys>.new` and `apps.<sys>.default` map to the same
  `writeShellApplication` wrapping `scripts/new.sh`.

## The `nix` CLI commands you will use

You do not need every subcommand. The ones that matter for this
tutorial:

### `nix run FLAKE#APP [-- ARGS...]`

Fetch, build, and run an `apps` output. This is how you invoke the
`new` wizard:

```console
$ nix run github:reflection-dev/nixops -- new my-fleet
```

The `--` separates arguments to `nix run` itself from arguments to
the wrapped program.

### `nix develop [FLAKE]`

Enter the flake's `devShells.<system>.default` shell. Inside an
instance repo this drops you into the ops toolbox: `ssh`,
`add-host`, `install-host`, `deploy`, and friends are all on
`PATH`, with the right `sops`, `age`, `nixos-anywhere`, etc.
alongside.

### `nix build [FLAKE#OUTPUT]`

Build an output. Puts a `./result` symlink into CWD.

### `nix flake update`

Refresh every input to its latest URL-resolved revision. Commit the
updated `flake.lock`.

### `nix flake lock --update-input NAME`

Refresh a single input. Handy when you want to bump `nixpkgs`
without touching `sops-nix`.

### `nix flake metadata [FLAKE]`

Print the description, resolved input URLs, and revision hashes.

### `nix flake check [FLAKE]`

Evaluate every check output. Used by CI to verify a flake still
evaluates and its deploys are well-formed.

### `nix eval [FLAKE#PATH]`

Evaluate an expression to a value and print it. Ops tooling uses
this heavily -- for example, `scripts/install-host.sh` uses
`nix eval --raw --impure --expr "(import ./hosts.nix).${NAME}.ip"`
to read the target's IP out of `hosts.nix`.

### `nix repl [FLAKE]`

Load a flake into an interactive REPL. Great for poking at what a
config actually evaluates to:

```console
$ nix repl .
nix-repl> :lf .
nix-repl> nixosConfigurations.web-1.config.networking.hostName
"web-1"
```

`:lf` = load a flake into the current namespace.

## `path:` inputs and dirty trees

While hacking on this repo (or any flake), you often want another
flake to consume your local checkout instead of a remote git URL.
You point its input at `path:/abs/path` (or a relative path). Two
things to know:

- Nix will only "see" **committed** content in a `path:` input by
  default. If you have uncommitted changes, they are invisible.
  This is intentional: flakes are supposed to be reproducible from
  git.
- You can override with `--impure` or by staging the tree, but
  during a course of hacking the friction is real. This is why the
  new-fleet wizard in this repo optionally `git init`s the scaffold
  and makes a first commit.

You will not usually have to know this -- but if you edit
`~/Projects/ref/nixops` while an instance repo references it as
`nixops.url = "path:...";`, and your changes seem invisible, this
is why.

## What next

You now know how flakes are structured. The next chapter takes what
you already know about Nix expressions and adds the NixOS module
system on top: how a NixOS configuration is assembled from many
small modules, each declaring `options` and `config`.

Next: [NixOS and the module system](nixos-and-modules.md)

## References for this chapter

- [nix.dev -- Flakes tutorial](https://nix.dev/concepts/flakes)
- [Nix Reference Manual -- flakes](https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-flake)
- [Nix Wiki (community) -- Flakes](https://wiki.nixos.org/wiki/Flakes)
- [Zero to Nix -- Flakes](https://zero-to-nix.com/concepts/flakes)
- [xeiaso.net -- Flake basics](https://xeiaso.net/blog/nix-flakes-1-2022-02-21/)
  -- opinionated intro with runnable examples.
