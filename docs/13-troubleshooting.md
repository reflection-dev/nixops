# 13 -- Troubleshooting

> Prerequisite: [Chapter 12](12-writing-host-modules.md).
> Time: read once now; grep back when stuck.
> Outcome: you recognise the common failure modes and know the first
> two or three things to try before falling back to the community.

Nothing here is exhaustive. It is the collection of "this took me
an hour the first time and 30 seconds the second" cases. When a
symptom is not covered, [NixOS Discourse](https://discourse.nixos.org/)
almost always has it -- search first, ask second.

## Nix / flake evaluation

### `error: experimental Nix feature 'nix-command' is disabled`

Flakes are not enabled. Fix `~/.config/nix/nix.conf` per Chapter 2:

```
experimental-features = nix-command flakes
```

If you install with the Determinate Nix Installer, this is set for
you.

### `error: getting status of '/nix/store/...': No such file or directory`

Store path was garbage-collected. `nix build` will refetch/rebuild
it. If you see this while a *shell* is running, exit and re-enter
`nix develop`.

### `error: git tree ... is dirty`

You are trying to build from a `path:` input whose git tree has
uncommitted changes. Either commit, or add `--impure` (careful --
"impure" is the tell that reproducibility is being bypassed). For
the wizard-driven flow this is not usually a problem; it hits you
when you are hacking on `nixops` itself as a `path:` input.

### `error: attribute 'foo' missing`

The output you asked for does not exist. `nix flake show` lists
what a flake actually exports. Typos in `nixosConfigurations.<name>`
are the most common cause.

### First `nix run` is enormous

The first fetch of nixpkgs is a few hundred MB. Subsequent runs
hit the store. If it stays slow, you may be missing a substituter:
`nix show-config | grep substituters`. `cache.nixos.org` is
mandatory; `nix-community.cachix.org` is nice-to-have.

### Slow evaluation

If `nix flake check` or `deploy` sits at "evaluating..." for
minutes on a small fleet: usually a runaway `with pkgs;` scope, a
recursive `imports`, or an accidental huge `builtins.readDir`.
Suspect the most recently edited module first.

## `install-host` (nixos-anywhere)

### `not enough memory` mid-install

`nixos-anywhere` copies the NixOS installer environment into the
target's memory. On sub-1GB VPSes this can be tight. Temporarily
bump the instance to 2GB for the install; scale back afterwards.

### `kexec failed`

Rare, but happens on ancient kernels or very locked-down cloud
images. Workaround: rent a bigger VPS for the install, or use
`nixos-generators` + boot from a rescue ISO once.

### `connection refused` after kexec

The installer's sshd did not start, or is on a different port. Wait
2 minutes; if still refused, reboot the target from the cloud
console and try again. If your target was configured with a
non-standard SSH port, that was the problem -- `nixos-anywhere`
assumes port 22 for the installer.

### Target is running NixOS, refuses to reinstall

The safety check in `install-host.sh`. Add `--force`:

```
$ install-host web-1 --force
```

Rebuilds from scratch; `/var/*` is lost, everything else survives.

### `sops.age.sshKeyPaths: file not found` after first boot

The `--extra-files` step of `install-host` planted
`/etc/ssh/ssh_host_ed25519_key`, but the target's `sshd` regenerated
its own key on first boot because sshd started before your key was
in place, or the file permissions ended up wrong. Verify:

```
[root@web-1:~]# ls -l /etc/ssh/ssh_host_ed25519_key
-r-------- 1 root root 411 ... /etc/ssh/ssh_host_ed25519_key
```

Should be mode 0400, owner root. Re-run `install-host --force` if
not.

## sops-nix

### `sops-decrypt.service` fails at boot

Journal shows "no age key found" or "failed to decrypt". Two
causes:

1. **Recipient mismatch.** The recipient in `.sops.yaml` for this
   host does not match `ssh-to-age -i
   /etc/ssh/ssh_host_ed25519_key.pub` on the host. Verify both;
   update `.sops.yaml` and `sops updatekeys secrets/<host>.yaml`.
2. **Missing `sopsFile`.** A `sops.secrets.foo` refers to a file
   that was not deployed. Check the `sopsFile` attribute path.

### `cannot decrypt secret on the laptop`

You typed `sops secrets/web-1.yaml` and got a decryption error.
Your `~/.config/sops/age/keys.txt` does not hold the private half
of any recipient of that file. Either:

- switch to the right age key file (`SOPS_AGE_KEY_FILE=...`), or
- ask an existing admin to re-encrypt the file for you: `sops
  updatekeys secrets/web-1.yaml` after adding your recipient.

### `sops updatekeys` says "up to date" but rules were edited

`sops updatekeys` compares against the file's own recorded MAC.
Force with `--yes` and re-run:

```
$ sops updatekeys --yes secrets/*.yaml
```

## deploy-rs

### "cannot resolve host"

deploy-rs SSHes to `nixops.host.ip` (Chapter 8). If your fleet
lives behind a bastion, add SSH config entries on your workstation
and swap `hostname` to the alias in your `mkDeploy`, or use
`ProxyJump` in `~/.ssh/config`.

### Deploy hangs at "activating configuration"

The activation is slow -- kernel initrd rebuild, large systemd
graph, etc. Give it up to 10 minutes on the first deploy after a
big change. `deploy --debug-logs` next time to see per-command
timing.

### Magic rollback keeps firing on a healthy host

The confirmation probe cannot reach the target from *your*
workstation. Almost always a network problem on your side (NAT,
firewall, ISP blackholing). `--no-magic-rollback` bypasses for one
deploy; fix the network for the long run.

### Deploy fails with "profile ... does not exist"

Someone garbage-collected the old profile from the target. Deploy
again -- deploy-rs will lay down a new profile.

### "SSH host key changed"

You reinstalled a host (`install-host --force` regenerates its
SSH host key). Your workstation's known_hosts still remembers the
old one. `ssh-keygen -R <ip>` and reconnect. Then re-encrypt
secrets for the host's new recipient (`install-host` does this
step for you).

## Devshell

### `add-host: hosts.nix not found in CWD`

You are not in the fleet repo root. `cd` in.

### `install-host: host 'X' not found in hosts.nix`

Typo in the name, or you forgot to `add-host` first. Names must
match exactly.

### Devshell hangs on entry

`nix develop` builds every runtime input the first time. On a
fresh laptop, that includes `nixos-anywhere`, `gum`, `sops`, and a
few dozen transitive deps. Give it 5 minutes on first entry;
subsequent entries hit the store.

### `deploy: command not found` inside `nix develop`

You entered the wrong shell. `nix develop` from the fleet repo
gets you the devShell with all the ops commands; `nix develop` in
some other directory gets you whatever that directory declares (or
nothing).

## NixOS runtime

### `journalctl -u foo` shows "activation failed"

Some part of the new generation refused to start. `journalctl -b`
shows the boot log; `journalctl -u foo` shows one service. Note:
if magic rollback fired, you may be looking at logs from the
already-rolled-back generation.

### "read-only filesystem" trying to edit `/etc/nginx/nginx.conf`

Correct. `/etc/nginx/nginx.conf` is a symlink into the Nix store,
and store paths are immutable. The right edit is in your NixOS
module (services.nginx options), followed by `deploy`.

### `nix-env -i` installed a package -- now what?

You are running imperative Nix on a NixOS host. Undo:
`nix-env -e <name>`. Better: put the package in the module and
deploy. `nix-env` on NixOS is a foot-gun; every non-root user
starts with an empty profile.

### Disk full

`nix-collect-garbage -d` reclaims the store. `nix-defaults.nix`
schedules this weekly; bump frequency per-host with
`nix.gc.dates`.

## Where to get more help

- **[NixOS Discourse](https://discourse.nixos.org/)** -- primary
  community forum. Search before asking.
- **[NixOS Wiki](https://wiki.nixos.org/)** -- community-maintained
  reference; often has the specific gotcha that manuals miss.
- **[NixOS Matrix (Element) rooms](https://nixos.org/community/#chat)** --
  `#nixos:matrix.org` for general chat, `#nixos-help:matrix.org`
  for how-do-I questions.
- **[nix.dev](https://nix.dev/)** -- if a manual can help you, it
  is here.
- **[search.nixos.org](https://search.nixos.org/)** -- options and
  packages.

## What next

You have the whole tutorial. Chapter 14 is the curated further-
reading list so you can go deeper into whichever piece piqued your
interest.

Next: [Chapter 14 -- Further reading.](14-further-reading.md)

## References for this chapter

- [NixOS Wiki -- Troubleshooting](https://wiki.nixos.org/wiki/Troubleshooting)
- [Zero to Nix -- FAQ](https://zero-to-nix.com/concepts/)
- [nix.dev -- FAQ](https://nix.dev/reference/faq)
- [Nix Reference Manual -- Errors](https://nix.dev/manual/nix/stable/error-messages/)
- [Mic92/sops-nix issues](https://github.com/Mic92/sops-nix/issues)
- [serokell/deploy-rs issues](https://github.com/serokell/deploy-rs/issues)
- [nix-community/nixos-anywhere issues](https://github.com/nix-community/nixos-anywhere/issues)
