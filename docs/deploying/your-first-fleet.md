---
title: "Your first fleet"
time: "30-60 minutes of walltime; ~15 minutes of hands-on typing"
---
# Your first fleet

> **Prerequisite:** the Foundations chapters ([What Nix is and why it matters](../foundations/what-is-nix.md) through [NixOS and the module system](../foundations/nixos-and-modules.md)) and [Secrets with sops-nix](sops-nix.md), [Remote install with nixos-anywhere](nixos-anywhere.md), and [Deploying with deploy-rs](deploy-rs.md). Also a Linux target you can wipe (a $5 VPS with root SSH access is ideal).
>
> **Outcome:** a git repo describing your fleet; a real NixOS host you installed remotely; a deploy round-trip.

This is the payoff chapter. Everything so far has been context.
Here you actually run the tools.

## Prerequisites checklist

- [x] Nix installed with flakes enabled ([Install Nix and enable flakes](../foundations/install-nix.md)). Verify:
  `nix --version` and `cat ~/.config/nix/nix.conf | grep experimental`.
- [x] A public SSH key pair on your laptop:
  `ls ~/.ssh/*.pub`. If none, `ssh-keygen -t ed25519`.
- [x] A Linux target you can wipe. Anything reachable via SSH as
  root: a fresh Hetzner/DigitalOcean/OVH VPS, an old ThinkPad, a
  Raspberry Pi. Get its IP.
- [ ] An age key (optional; wizard offers to generate one). If you
  already have `~/.config/sops/age/keys.txt`, we will use it.

## Step 1: run the wizard

From any directory (the wizard creates a new subdirectory for the
fleet):

```console
$ nix run github:reflection-dev/nixops -- new my-fleet
```

`nix run` fetches this repo (first time) and executes its default
app, which is the `new` scaffolder. The `--` after `nixops`
separates arguments to `nix run` itself from arguments to the
wrapped program ([Flakes](../foundations/flakes.md) covered this).

The wizard asks:

1. **Description**. Freeform. Defaults to `my-fleet`.
2. **SSH key**. Auto-detected from `~/.ssh/*.pub`. Pick one; it
   becomes root's `authorized_keys` on every host in the fleet.
   Add more later by editing `flake.nix`.
3. **age recipient**. Auto-detected from
   `~/.config/sops/age/keys.txt`. If none, offers to generate. This
   is the admin key -- your laptop's ability to decrypt secrets.
4. **Admin recipient name**. The alias used in `.sops.yaml` (default
   `admin_${USER}`). Cosmetic; pick something meaningful if you
   will have multiple admins.
5. **`git init`?** Recommended yes; the wizard makes a first commit
   so the tree is committed ([Flakes](../foundations/flakes.md) explains why this matters
   for `path:` inputs).

When it finishes:

```text
created ./my-fleet/

Next:
  cd my-fleet
  nix develop
  add-host <name>
  install-host <name>
```

## Step 2: inspect what was scaffolded

```console
$ cd my-fleet
$ ls -a
.gitignore  .sops.yaml  flake.nix  hosts.nix  README.md
```

Five files. Open each in your editor. What you see:

- **`flake.nix`** -- inputs (nixops, and follows for
  nixpkgs/sops-nix/deploy-rs) and outputs
  (`nixosConfigurations`, `deploy.nodes`, `checks`, `devShells`).
  The `sshKeys = [ ... ]` list holds the key you picked. This is
  the whole flake for the fleet.
- **`hosts.nix`** -- currently `{ }`. Every host you add lands here
  as a key.
- **`.sops.yaml`** -- one entry for your admin recipient, empty
  `creation_rules`. `install-host` grows both when hosts are added.
- **`.gitignore`** -- ignores `result` symlinks, `.direnv/`, and
  `secrets/*/` (where install-host stashes temporary host-key
  material).
- **`README.md`** -- a one-page reminder of the ops commands.

[Anatomy of an instance repo](anatomy-of-an-instance.md) walks each file in detail. For now, glance and move on.

## Step 3: enter the devShell

```console
$ nix develop
nixops devShell -- 0 host(s) in inventory
```

You are now in a shell where `ssh`, `add-host`, `install-host`,
`update-secrets`, `deploy`, plus `sops`, `age`, `ssh-to-age`,
`nixos-anywhere`, `jq`, `gum` are on `PATH`. Confirm:

```console
$ which ssh
/nix/store/...-ssh/bin/ssh
$ which install-host
/nix/store/...-install-host/bin/install-host
```

Each is a `pkgs.writeShellApplication` from `lib/mkDevShell.nix`,
wrapping the corresponding script in `scripts/`.

The shell also generated an `ssh_config` that maps your host names
(none yet) to their IPs from `hosts.nix`.

**Tip:** using `direnv` with the `use flake` hook makes entering
the devShell automatic when you `cd` into the repo. See
[direnv + nix-direnv](https://github.com/nix-community/nix-direnv).

## Step 4: add a host to the inventory

```console
$ add-host web-1
IP address: 1.2.3.4
```

`add-host`:

1. checks `web-1` is not already in `hosts.nix`;
2. creates `hosts/web-1/hardware-configuration.nix` as a stub
   (empty module -- the real one comes back from `install-host`);
3. appends an entry to `hosts.nix`:

    ```nix
    web-1 = {
      ip      = "1.2.3.4";
      modules = [ ./hosts/web-1 ];
    };
    ```

Nothing has touched the target yet. `hosts.nix` is data; the wizard
scaffolds the directory but does not install anything.

## Step 5: install the host

Now the real thing. Make sure you have root SSH access to the
target from your workstation:

```console
$ ssh root@1.2.3.4 uname -a
Linux debian-12 6.1.0-... x86_64 GNU/Linux
```

Then, from inside the devShell in your fleet repo:

```console
$ install-host web-1
```

This is going to do everything you learned in [Secrets with sops-nix](sops-nix.md), [Remote install with nixos-anywhere](nixos-anywhere.md), and [Deploying with deploy-rs](deploy-rs.md), in
order. Watch the output; every line maps to something you have
seen:

1. **IP lookup + NixOS safety check.** If the target is already
   NixOS, refuses without `--force`.
2. **`.sops.yaml` doesn't need updates** (since this scaffold has
   no `sops.secrets.*` declared yet). If your host module did
   declare them, `install-host` would generate a host key, add the
   recipient to `.sops.yaml`, and prompt for values.
3. **`nixos-anywhere --flake .#web-1 root@1.2.3.4`.** Kexec, wipe,
   install, reboot. Watch the SSH connection drop once and come
   back.

Coffee break. First deploy on a small VPS is 5-10 minutes.

When it finishes, the host has been reinstalled with your NixOS
configuration. Verify:

```console
$ ssh web-1
[root@web-1:~]# nixos-version
25.11.20260315.abcdef1 (Vicuna)
```

`ssh web-1` works because the devShell's generated `ssh_config`
resolves the name to its IP. `nixos-version` confirms you are on
NixOS.

## Step 6: change something and deploy

You have a running NixOS host, installed from a fresh Debian, with
sshd hardened, a firewall, and root's authorized_keys set to your
laptop key. What's next?

Let's open the firewall for HTTP. Edit `hosts.nix`:

```nix
web-1 = {
  ip      = "1.2.3.4";
  modules = [ ./hosts/web-1 ];
  nixops.firewall.allowedTCPPorts = [ 80 443 ];  # <-- add this
};
```

Any field on the inventory entry that is not `ip`, `system`, or
`modules` becomes an inline module fragment for that host (see
[NixOS and the module system](../foundations/nixos-and-modules.md) for the `specialArgs` + inline-module trick in
`mkNixosConfigs`). So this line is equivalent to writing a module
that sets `nixops.firewall.allowedTCPPorts = [ 80 443 ];` -- which
`modules/firewall.nix` picks up.

Now deploy:

```console
$ deploy web-1
```

deploy-rs:

- builds the new closure on your laptop;
- copies it to `web-1`;
- activates it (systemd reloads, iptables is updated);
- pings the target from your laptop;
- if the ping fails, rolls back.

Verify:

```console
$ ssh web-1
[root@web-1:~]# iptables -L -n | grep -E "80|443"
```

## Step 7: understand what you now have

- **`git status`** on the fleet repo shows the changes to
  `hosts.nix`. Commit them: the git history of this repo is now
  the change log of your fleet.
- **`nix flake show`** lists every output: your one
  `nixosConfigurations.web-1`, one `deploy.nodes.web-1`, one
  devShell, etc.
- **Rollback**: if magic-rollback did not fire on its own, the
  clean path is `git checkout <good-commit> && deploy web-1 && git
  checkout main`. As a last resort when the host is unreachable
  over SSH, console in and run `nixos-rebuild switch --rollback`.
- **Adding a second host**: repeat Step 4-5 with a new name and a
  new IP. `deploy` (no arg) deploys both concurrently.

## The whole loop, once you know it

```text
edit *.nix           # change desired state
git add + commit     # snapshot it
deploy [name]        # ship it
```

If a change involves secrets: `update-secrets [name]` before
`deploy`. If a change involves a new host: `add-host <name>` +
`install-host <name>`. That is the entire operational surface.

## What next

[Anatomy of an instance repo](anatomy-of-an-instance.md) walks every file in the instance repo in detail so you
know what to change when. [Day-two operations](../operating/day-two-operations.md) covers the day-two loop -- key
rotation, adding admins, splitting hosts across environments,
diagnosing a failed deploy. [Writing host-specific modules](../operating/writing-host-modules.md) shows how to write your
own host-specific modules (adding a real service, a disko layout).

Next: [Anatomy of an instance repo](anatomy-of-an-instance.md)

## References for this chapter

- [Zero to Nix -- a first NixOS system](https://zero-to-nix.com/concepts/nixos)
  -- friendly walkthrough of building a NixOS system from scratch,
  complements this chapter well.
- [NixOS Manual -- installing NixOS](https://nixos.org/manual/nixos/stable/#ch-installation)
- [NixOS Discourse -- getting started category](https://discourse.nixos.org/c/learn/9)
- Your own fleet's `README.md` -- the wizard scaffolded a
  short-form version of this chapter into it.
