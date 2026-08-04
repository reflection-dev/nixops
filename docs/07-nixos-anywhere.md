# 07 -- Remote install with nixos-anywhere

> Prerequisite: [Chapter 6](06-sops-nix.md).
> Time: 30 minutes.
> Outcome: you know how a Linux-of-any-kind target becomes a NixOS
> host in one command, without a rescue image or console access;
> you can read `scripts/install-host.sh` and understand every step.

`nixos-anywhere` is a small tool from `nix-community` that installs
NixOS on any reachable Linux target -- a cheap VPS running Debian,
an EC2 Ubuntu, an OVH rescue-mode box, a repurposed Raspberry Pi,
even a running NixOS box being re-imaged. It does the work over a
plain SSH connection; no rescue-image download, no console access,
no PXE.

Upstream: [nix-community/nixos-anywhere](https://github.com/nix-community/nixos-anywhere).

## What it needs

- **Root SSH** to the target. The tool needs to execute privileged
  commands: partition disks, install a boot loader, kexec a new
  kernel. Password auth or key auth both work; this repo assumes
  key auth.
- **At least ~1 GB of RAM free** on the target after the tool
  copies in the NixOS installer environment. Very small VPS
  instances can be tight but usually work.
- **A working kernel with kexec** on the target. Any mainstream
  Linux distro from the last decade has this.
- **Optional but recommended:** a disko config in your NixOS
  configuration. If you do not have one, `nixos-anywhere` will use
  a set of sensible partitioning defaults, but for anything past
  toy fleets you want disks under version control (see below).

## What it does, step by step

`nixos-anywhere` runs the following on your workstation. Every step
is scripted; the tool is a wrapper around Nix builders and SSH:

1. **Build the installer environment.** A minimal NixOS root that
   knows how to partition, format, and unpack a target
   configuration. Built locally via Nix; can be pushed from cache.
2. **`scp` the environment to the target.** Copied into the
   target's memory (via `/dev/shm` when possible).
3. **Kexec into the installer.** The running Debian/Ubuntu/whatever
   is replaced in-memory by the NixOS installer *without a reboot*.
   The SSH connection reconnects automatically after a few seconds.
4. **Partition and format** the target's disks according to a disko
   configuration (or the fallback defaults).
5. **Copy the NixOS closure** for the target configuration onto the
   new partitions.
6. **Copy `--extra-files`** into the new root (this is how host
   keys get injected, see below).
7. **Install the boot loader** and reboot.
8. **Wait for the target to come back on SSH** and print a success
   message.

Total time: 3-10 minutes depending on connection speed and
substitution cache hits.

## Why kexec

Because the target may be a rented VPS with no console access and
no way to boot alternative media. Kexec lets you replace the
running kernel from userspace without touching the boot loader.
Once the NixOS installer is in memory, the tool can wipe the disks
freely because nothing on them is running.

You can watch the kexec happen in the SSH session -- your
connection drops for ~5 seconds and the new session comes up on the
NixOS installer. If the tool detects you are already on NixOS (via
`/etc/NIXOS`), it can skip the kexec and go straight to the
partition + install step.

## `--extra-files` and host keys

The `--extra-files DIR` flag: the tool copies `DIR`'s tree straight
onto the target's new root filesystem after the closure is copied
but before the reboot. `install-host` uses this to plant the target's
`/etc/ssh/ssh_host_ed25519_key` before first boot, so:

- the host has the *same* SSH host key across all its future life
  (no re-fingerprinting after every reinstall);
- sops-nix (Chapter 6) can decrypt on the very first boot, because
  the age recipient it needs is derived from that host key.

Only files that must exist *before* first boot need to go through
`--extra-files`. Everything else should be in the NixOS config.

## The disko question

`nixos-anywhere` can partition on its own using a builtin fallback,
but for real deployments you want to declare disk layout as code.
[nix-community/disko](https://github.com/nix-community/disko) does
that: a small module that turns a Nix-language description of
partitions/filesystems/RAID into an idempotent partitioning script.

This repo has **no disko module** on purpose (see the "Non-goals"
section of the top-level README): every fleet's storage story is
different, and shipping a one-size-fits-all disko config would be
wrong more often than right. When you scaffold an instance repo,
you drop your own `hosts/<name>/disko.nix` next to
`hardware-configuration.nix`, and reference it from the host's
modules.

Chapter 12 has a concrete example. For now, the shape:

```
# hosts/web-1/disko.nix
{
  disko.devices.disk.main = {
    device = "/dev/vda";
    type   = "disk";
    content = {
      type = "gpt";
      partitions = {
        boot = { size = "1G"; type = "EF00"; content = { type = "filesystem"; format = "vfat"; mountpoint = "/boot"; }; };
        root = { size = "100%"; content = { type = "filesystem"; format = "ext4"; mountpoint = "/"; }; };
      };
    };
  };
}
```

`nixos-anywhere` reads this via the NixOS configuration and
executes it as part of its partition step.

Disko docs: [nix-community/disko README](https://github.com/nix-community/disko)
and the [disko examples directory](https://github.com/nix-community/disko/tree/master/example).

## Reading `install-host.sh`

Open [`scripts/install-host.sh`](../scripts/install-host.sh). The
whole file is ~170 lines; below is the map. The interesting
sections in order:

1. **Argument parsing** (lines 12-24). `--force` overrides the
   safety check that refuses to reinstall a target that is already
   NixOS. Without `--force`, if the target has `/etc/NIXOS`, the
   script bails.
2. **IP lookup** (lines 33-39). Uses `nix eval --raw --impure
   --expr "(import ./hosts.nix).${NAME}.ip"` to read the IP out of
   the inventory. This is the only place the shell script has to
   evaluate Nix; everything else is plain shell.
3. **NixOS safety check** (lines 44-51). SSHes with `BatchMode`
   (no interactive prompts, fail fast) and looks for `/etc/NIXOS`.
   Refuses to proceed unless `--force`.
4. **Does the host declare sops secrets?** (lines 55-60). Query
   `sops.secrets` on the host's config; if empty, skip the whole
   sops preparation. This lets you bootstrap a host with no
   secrets and only wire sops in later.
5. **SSH host key generation + `.sops.yaml` injection** (lines 66-149).
   Generate a fresh ed25519 host key locally, derive the age
   recipient with `ssh-to-age`, add it to `.sops.yaml` as an anchor
   plus a `creation_rule` for `secrets/<name>.yaml`, run `sops
   updatekeys` on any existing secret file so the new recipient can
   decrypt it.
6. **Prompt for missing secrets** (line 152). Calls
   `update-secrets $NAME` to walk `sops.secrets.*` and prompt for
   any keys not yet set.
7. **Build the `--extra-files` tree** (lines 155-161). Copies the
   host key into `EXTRA/etc/ssh/`, preserving mode 0400.
8. **Invoke `nixos-anywhere`** (lines 165-168):

    ```
    nixos-anywhere \
      --flake ".#${NAME}" \
      --extra-files "$EXTRA" \
      "root@${IP}"
    ```

9. **Clean up** (lines 172-175). Delete the local copy of the host
   private key; from now on it only lives on the target.

That is the whole flow. Reading the script in one sitting after
this chapter should feel entirely legible.

## When things go wrong mid-install

`nixos-anywhere` fails loudly. Common causes:

- **`nixos-anywhere: kexec failed`** -- target's kernel refuses to
  kexec (rare but possible on old hosts). Workaround: use a rescue
  image or another VPS.
- **`nixos-anywhere: not enough memory`** -- target has less than
  ~1 GB free after the installer is copied. Bump the instance
  size for the install; you can scale back later.
- **`connection refused` after kexec** -- the installer's sshd
  did not start, usually because the target's SSH port was
  non-standard and the installer is bound to 22. Reboot the
  target (its old system is still on disk if partitions have not
  been formatted yet).
- **"disk full" during copy** -- the closure is bigger than the
  target's root partition. Use a bigger disk or trim modules.

Re-running `install-host` after a partial failure is safe: it is
idempotent up to disk formatting, and repeats the whole flow. Once
the target is running NixOS it will refuse to reinstall without
`--force`.

## Alternatives

- **`nixos-generators` + boot from ISO**. If you have console
  access and prefer a rescue-image workflow. Slower to iterate.
- **`nixos-infect`** -- older tool that converts a live
  Debian/Ubuntu to NixOS in place. Fragile; `nixos-anywhere` has
  largely superseded it.
- **PXE + `nixos-installer`** -- the "properly configured data
  centre" path. Overkill for small fleets.

For anything that fits on a laptop-plus-SSH workflow (which is
most fleets), `nixos-anywhere` is the tool.

## What next

Now that you can plant a NixOS system on a bare Linux target, the
next chapter covers how you keep updating that system over time --
in a way that survives partial failures and lets you roll back
safely.

Next: [Chapter 8 -- Deploying with deploy-rs.](08-deploy-rs.md)

## References for this chapter

- [nix-community/nixos-anywhere](https://github.com/nix-community/nixos-anywhere)
- [nixos-anywhere docs](https://numtide.github.io/nixos-anywhere/) --
  full option reference and examples.
- [nix-community/disko](https://github.com/nix-community/disko) --
  disk layout as code.
- [Zero to Nix -- deploying NixOS](https://zero-to-nix.com/concepts/deployment)
  -- broader ecosystem context.
- [NixOS Wiki -- nixos-anywhere](https://wiki.nixos.org/wiki/Nixos-anywhere)
- [NixOS Wiki -- disko](https://wiki.nixos.org/wiki/Disko)
- [NixOS Discourse -- nixos-anywhere tag](https://discourse.nixos.org/tag/nixos-anywhere)
- [Numtide blog -- nixos-anywhere post](https://numtide.com/blog/hello-nixos-anywhere-installing-nixos-everywhere/)
  -- the original announcement, still a good overview.
