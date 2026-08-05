---
time: "30 minutes"
---
# 08 -- Deploying with deploy-rs

> **Prerequisite:** [Chapter 7](nixos-anywhere.md).
>
> **Outcome:** you know what `deploy-rs` does that `nixos-rebuild` does not; you understand magic-rollback; you can read `lib/mkDeploy.nix` and the `deploy.nodes` output.

Once a NixOS host exists (courtesy of Chapter 7), you need to keep
updating it -- new package versions, new services, security fixes.
In this repo the answer is one command from the devShell:

```
$ deploy [name]
```

That is the entire operator-facing surface for rolling out changes.
The rest of this chapter explains what `deploy` is built on --
`deploy-rs` from [serokell/deploy-rs](https://github.com/serokell/deploy-rs),
which layers push-model deployment, magic-rollback, concurrency,
and dry-run on top of what NixOS's built-in `nixos-rebuild` does
locally. You will not run `nixos-rebuild` yourself unless you are
recovering an unreachable host from its console; every routine
change goes through `deploy`.

The fleet-side wins over "SSH in and rebuild by hand":

- **Push from your workstation**, not pull from the target. The
  workstation has the flake, the git history, the credentials.
- **Automatic rollback** if the new configuration turns out to be
  wrong (e.g. it broke sshd -- goodbye, host).
- **Concurrent deploy** across many hosts without hand-scripting a
  loop.
- **Dry-run / check** before touching anything.

## The model

`deploy-rs` reads a `deploy` output from your flake. That output is
an attribute set:

```
deploy.nodes.<name>.hostname       # where to ssh
deploy.nodes.<name>.sshUser        # as whom
deploy.nodes.<name>.profiles.<p>.path  # the store path to activate
```

For each node you deploy, it:

1. Builds the new closure locally (or fetches it from a cache).
2. `nix-copy-closure`s the closure over SSH to the target.
3. Activates the new profile on the target (systemd reload,
   service restarts, symlink flips).
4. **Waits** for the target to come back on SSH from your
   workstation (this is the magic-rollback probe).
5. **If the probe fails** within a timeout, tells the target to
   roll back to the previous generation. Because NixOS generations
   are atomic, "roll back" is one symlink swap and one systemd
   reload.

Step 4+5 is the killer feature. Deploy an sshd config with a typo?
Your workstation stops being able to reach the box; deploy-rs
notices; the target rolls itself back to the last known-good
config; your next SSH attempt reaches the old, working sshd. You
did not need console access; you did not have to remember to keep
the previous SSH session open.

## `mkDeploy` in this repo

Look at [`lib/mkDeploy.nix`](../lib/mkDeploy.nix). It is 13 lines
including a comment:

```
{ deploy-rs }:
nixosConfigurations:
builtins.mapAttrs (_name: nixosConfig: {
  hostname = nixosConfig.config.nixops.host.ip;
  sshUser  = "root";
  profiles.system = {
    user = "root";
    path = deploy-rs.lib.${nixosConfig.pkgs.stdenv.hostPlatform.system}.activate.nixos
      nixosConfig;
  };
}) nixosConfigurations
```

Read it now, with Chapter 3 fresh in mind:

- Function taking `{ deploy-rs }` -> function taking a
  `nixosConfigurations` attrset -> a mapAttrs over it.
- For each `(_name, nixosConfig)`, produce a deploy-rs node:
  - `hostname` from the host's declared IP (from `nixops.host.ip`,
    which `mkNixosConfigs` sets from `hosts.nix`).
  - `sshUser = "root"`.
  - `profiles.system.path` is deploy-rs's activation script for
    that NixOS config on that architecture.

The instance flake wires it in:

```
deploy.nodes = nixops.lib.mkDeploy self.nixosConfigurations;
checks.${system} = deploy-rs.lib.${system}.deployChecks self.deploy;
```

`checks` runs `nix flake check` against every declared deploy so
CI can catch a bad flake before you touch a real host.

## Activation modes

`deploy-rs` activates by writing a new profile symlink and running
NixOS's `switch-to-configuration switch`. That is the same thing
`nixos-rebuild switch` does locally; the difference is `deploy-rs`
did the *build* on your workstation, copied the *closure*, and
runs the *activation* remotely.

You can pick other activation verbs per-profile:

- `activate.nixos` -- switch (default; what this repo uses).
- `activate.nixos-boot` -- set as default for next boot, do not
  activate now.

For most fleets, `switch` is what you want.

## Magic rollback

"Magic rollback" is deploy-rs's name for the probe-and-rollback
behaviour. It works because NixOS activation is atomic and
reversible:

1. Before activation, deploy-rs remembers the previous profile
   symlink target.
2. It activates the new one.
3. It runs a small "confirmation" probe from your workstation
   (`ssh <target> true` by default) with a timeout.
4. If the probe fails, deploy-rs sends the target a rollback
   command that flips the symlink back and runs
   `switch-to-configuration switch` on the previous generation.

Disable it with `--no-magic-rollback` if you know the change breaks
your ability to reach the host but you want it anyway (e.g. moving
sshd to a new port). Use with care.

Reference: [deploy-rs README -- Magic Rollback](https://github.com/serokell/deploy-rs#magic-rollback).

## The `deploy` wrapper in this repo

`scripts/deploy.sh` is a two-condition wrapper. From the source:

```
if [ "$#" -eq 0 ]; then
  exec deploy .
fi

NAME="$1"
shift
case "$NAME" in
  -*|.*)  exec deploy "$NAME" "$@" ;;
  *)      exec deploy ".#${NAME}" "$@" ;;
esac
```

- No args -> deploy every node in the current flake.
- `deploy <name>` -> deploy just `<name>`.
- Passthrough for any flag (`deploy --help`, `deploy --skip-checks`,
  `deploy web-1 --dry-activate`).

## `nix flake check` and CI

`deploy-rs.lib.<system>.deployChecks` produces a set of derivations
that validate:

- every `deploy.nodes.<name>` refers to a real system;
- the system's derivation actually evaluates and builds;
- there are no schema errors in the deploy config.

An instance flake wires this into `checks.<system>` so `nix flake
check` runs them. CI running `nix flake check` on every PR catches
"the deploy config is broken" before you find out at 2am.

## Concurrency and ordering

By default, `deploy .` deploys every node concurrently. Options:

- `--target-hostname X` -- run the whole thing against just one
  hostname, ignoring what the flake says.
- `--interactive` -- pause between nodes and ask.
- `--auto-rollback` and `--magic-rollback` -- both on by default.
- `--dry-activate` -- build + copy + do everything except the final
  switch.

If you want a specific order (deploy the database before the web
tier) you have two options: split into two `deploy` invocations, or
list dependencies via `nodes.<name>.magicRollback = false; ...`.
For small fleets, calling `deploy db-1 && deploy web-1` is
perfectly fine.

## Common gotchas

- **"unable to resolve host"** -- deploy-rs SSHes to
  `nixops.host.ip` and expects that to be reachable from your
  workstation. If your fleet lives behind a bastion, use SSH
  config aliases (`~/.ssh/config`) or `ProxyJump`.
- **"cannot decrypt secret"** on first-boot after deploy -- you
  changed `.sops.yaml`'s recipients but forgot to `sops updatekeys
  secrets/*.yaml`. See Chapter 6.
- **Deploy hangs on activation** -- the target is applying a
  slow change (e.g. rebuilding a kernel initrd). Give it a few
  minutes; use `deploy --debug-logs` next time to see what runs.
- **Magic rollback keeps triggering** -- the confirmation probe
  cannot reach the target from your workstation, even though the
  target is healthy. Almost always a network/NAT/firewall issue on
  *your* side, not the target's. `--no-magic-rollback` will bypass
  it for one deploy; fix the network for the long run.
- **Wrong host key after reinstall** -- if you `install-host
  --force`ed and did not preserve the SSH host key, your
  workstation refuses to reconnect. `ssh-keygen -R <ip>` and re-add.

## Alternatives

You will not switch away from `deploy` in this repo -- it is the
one command the devShell exposes. For context, though, the Nix
world has several other deploy tools with different tradeoffs:

- **`nixos-rebuild switch --target-host user@host`** -- the
  official upstream option, invoked directly. Works, no magic
  rollback, needs the target to have Nix installed
  (`nixos-rebuild` copies the closure via `nix-copy-closure`).
  Fine for one-off manual deploys outside a fleet framework.
- **[Colmena](https://github.com/zhaofengli/colmena)** -- similar
  to `deploy-rs`, opinionated in a different direction (declarative
  fleet layout in the flake). Popular alternative.
- **[NixOps4](https://github.com/nixops4/nixops4)** -- the official
  next-generation deploy tool from the NixOS Foundation. Still
  maturing.
- **[disnix](https://github.com/svanderburg/disnix)** -- older;
  distributed *service* deployment (not whole systems). Niche.

`nixops` (this repo, not the historical tool) picks `deploy-rs` for
its magic-rollback and small dependency surface. You can swap by
rewriting `lib/mkDeploy.nix` and the `deploy` script -- the rest of
the fleet base does not care.

## What next

You now have the whole stack: Nix (Chapter 2-4), NixOS (Chapter 5),
sops-nix (Chapter 6), nixos-anywhere (Chapter 7), deploy-rs (this
chapter). Chapter 9 uses all of it to walk through actually
scaffolding, installing, and deploying a fleet from zero.

Next: [Chapter 9 -- Your first fleet.](your-first-fleet.md)

## References for this chapter

- [serokell/deploy-rs](https://github.com/serokell/deploy-rs) --
  README is short and worth reading.
- [Serokell blog -- deploy-rs announcement](https://serokell.io/blog/deploy-rs)
  -- the design rationale.
- [Zero to Nix -- Deploying NixOS](https://zero-to-nix.com/concepts/deployment)
- [NixOS Wiki -- Comparison of remote deployment tools](https://wiki.nixos.org/wiki/Comparison_of_deployment_tools)
- [NixOS Discourse -- deployment category](https://discourse.nixos.org/c/dev/deploy/50)
- [Colmena docs](https://colmena.cli.rs/) -- if you want to compare
  the alternative firsthand.
