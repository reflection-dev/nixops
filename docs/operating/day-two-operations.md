---
title: "Day-two operations"
time: "30 minutes for the reading; the rest is muscle memory"
---
# Day-two operations

> **Prerequisite:** [Anatomy of an instance repo](../deploying/anatomy-of-an-instance.md).
>
> **Outcome:** you know every routine ops command by rote; you know what to do when adding a host, adding a secret, adding an admin, or rolling out a config change.

[Your first fleet](../deploying/your-first-fleet.md) walked one full loop. This chapter is the reference for
the *repeated* loops: what to run, in what order, when the fleet
already exists.

Every command below runs from inside your fleet repo, inside the
devShell (`nix develop`).

## The five commands

| command                 | what it does                                                          |
| ----------------------- | --------------------------------------------------------------------- |
| `ssh <name>`            | ssh via the auto-generated config from `hosts.nix`                    |
| `add-host <name>`       | prompt for IP; scaffold `hosts/<name>/`; append to `hosts.nix`        |
| `install-host <name>`   | first-boot install via `nixos-anywhere` + sops recipient + secrets    |
| `update-secrets [name]` | interactively fill any `sops.secrets.*` values not yet set            |
| `set-secret <host> <key> <file>` | non-interactive: write one secret from a file or stdin (`-`) |
| `deploy [name]`         | roll the current flake out to one host or the whole fleet             |

Plus (`nix flake update`, `sops`, `age`, `git`) available via
`PATH` in the devShell.

## Rolling out a config change

The most common loop.

```console
$ vim hosts/web-1/default.nix       # or wherever you edit
$ git status                        # sanity: only expected changes
$ deploy web-1                      # or `deploy` for the whole fleet
```

`deploy-rs` builds locally, ships the closure, activates, and
magic-rollback-probes. If the probe fails, you are back on the
previous generation and the deploy command exits non-zero.

Commit the change once the deploy succeeds:

```console
$ git add hosts/web-1/default.nix
$ git commit -m "web-1: enable metrics endpoint"
```

Order matters: **deploy before commit** so that if the deploy
fails, your git tree still describes the last-known-good state.
Only commit what you have proven works.

## Adding a host

```console
$ add-host db-1
IP address: 5.6.7.8
$ install-host db-1
```

`add-host` is inventory-only; `install-host` does the actual
first-boot install. [Remote install with nixos-anywhere](../deploying/nixos-anywhere.md) covers what `install-host` runs.

After it finishes:

```console
$ ssh db-1
[root@db-1:~]# nixos-version
```

Grab `hardware-configuration.nix` from the target (nixos-anywhere
prints instructions) and drop it into `hosts/db-1/`, replacing the
stub. Commit.

## Reinstalling a host

If a host is in an unrecoverable state, or you want to swap
hardware:

```console
$ install-host <name> --force
```

`--force` bypasses the "target is already NixOS" refusal. The
same age recipient stays in `.sops.yaml` (because a re-install
generates a new SSH host key -> new age recipient); `install-host`
updates the anchor in place and re-encrypts existing secrets with
`sops updatekeys`. All you lose is `/var/*` on the target -- your
NixOS config, secrets, and identity survive because they live in
the fleet repo.

## Adding a secret to a host

Two-step:

1. Declare it in the host's NixOS module.

    ```nix
    # hosts/web-1/default.nix
    sops.secrets.api_token = {
      sopsFile = ../../secrets/web-1.yaml;
      owner    = "myservice";
    };

    systemd.services.myservice.serviceConfig.EnvironmentFile =
      config.sops.secrets.api_token.path;
    ```

2. Fill in the value.

    ```console
    $ update-secrets web-1
    web-1 :: api_token
    value for api_token: ****
    ```

    `update-secrets` reads the declared `sops.secrets.*`, notices
    `api_token` is missing from `secrets/web-1.yaml`, prompts you,
    encrypts, writes.

Then deploy:

```console
$ deploy web-1
```

The service comes up with `/run/secrets/api_token` in place. If
you deployed *before* running `update-secrets`, sops-nix would
have failed at boot and (thanks to magic rollback) the target
would still be on the previous config.

## Rotating a secret

Editing an existing secret in place:

```console
$ sops secrets/web-1.yaml
```

Drops you into `$EDITOR` with the plaintext. Change the value,
save, exit. `sops` re-encrypts.

Then `deploy web-1` -- sops-nix decrypts the new value, writes
`/run/secrets/api_token`, and restarts services that pinned the
encrypted file as a restart trigger. Wire it up with
`restartTriggers = [ config.sops.secrets.api_token.sopsFile ];` on
the systemd service -- the `.sopsFile` path is what Nix hashes, so
the trigger fires whenever the encrypted YAML changes.

## Adding an admin

Two edits, one round of `sops updatekeys`.

1. Get the new admin's SSH pubkey; append to `flake.nix`:

    ```nix
    sshKeys = [
      "ssh-ed25519 AAAA... you@laptop"
      "ssh-ed25519 AAAA... colleague@laptop"
    ];
    ```

2. Get their age recipient (they run `age-keygen -o
   ~/.config/sops/age/keys.txt` and give you `age1...`); append to
   `.sops.yaml`:

    ```yaml
    keys:
      - &admin_you        age1youdefinitely...
      - &admin_colleague  age1theircolleaguekey...
      - &web-1            age1web1derived...
    ```

3. Add them to every `creation_rule`:

    ```yaml
    creation_rules:
      - path_regex: secrets/web-1\.yaml$
        key_groups:
          - age: [ *admin_you, *admin_colleague, *web-1 ]
    ```

4. Re-encrypt every existing secret file for the new recipient
   set:

    ```console
    $ sops updatekeys secrets/*.yaml
    ```

5. Deploy:

    ```console
    $ deploy
    ```

    Root's `authorized_keys` picks up the new key on every host.

Commit.

## Removing an admin (e.g. a laptop was lost)

Reverse of the above:

1. Remove their line from `sshKeys` and from `.sops.yaml`.
2. `sops updatekeys secrets/*.yaml` -- the file re-encrypts
   without the removed recipient. **Any data they saw before this
   point is still known to them**; changing the encryption
   recipients does not un-read it. Rotate the underlying secret
   values (Section "Rotating a secret") for anything they should
   no longer know.
3. Deploy. Root's `authorized_keys` drops the pubkey; they can no
   longer SSH.

## Reading remote logs and status

```console
$ ssh web-1
[root@web-1:~]# journalctl -u nginx --since "1 hour ago"
[root@web-1:~]# systemctl status
[root@web-1:~]# nixos-version
[root@web-1:~]# nix-store --gc-roots        # see what's pinned
```

Nothing NixOS-specific here; you have the standard systemd toolbox
plus the Nix ones.

## Rolling back a bad deploy

If magic rollback did not fire (rare -- usually happens when the
change is bad but does not affect the probe path), roll back from
your workstation by redeploying an older commit:

```console
$ git checkout <known-good-commit>
$ deploy web-1
$ git checkout main
```

Same `deploy` command you use for a forward change; git is the
version control.

Only if the host is completely unreachable over SSH (so `deploy`
cannot connect), console in and roll back on the target itself:

```console
[root@web-1:~]# nixos-rebuild switch --rollback
```

That is the escape hatch, not the routine path.

Every previous generation is on disk under `/nix/var/nix/profiles/`
until GC runs; by default `nix-defaults.nix` sets GC to weekly with
30d retention, so you have a month of history to roll back to.

## Cleaning up the store

If a target starts running out of disk:

```console
[root@web-1:~]# nix-collect-garbage --delete-older-than 7d
```

`nix-defaults.nix` already runs weekly GC with 30d retention. Bump
the frequency or the retention window per-host by setting
`nix.gc.dates` and `nix.gc.options` in that host's inline module
in `hosts.nix`.

## Refreshing dependencies

```console
$ nix flake update
$ git diff flake.lock            # see which versions bumped
$ nix flake check                # every deploy still evaluates
$ deploy                         # roll out
```

Commit `flake.lock` afterwards.

Bump just one input (e.g. only `nixops` because you shipped a
change to it upstream):

```console
$ nix flake update nixops
```

## Split deploys

If some hosts must be updated in a specific order (e.g. deploy the
DB first, then the app tier):

```console
$ deploy db-1
$ deploy app-1 app-2 app-3       # not supported by the wrapper; use plain deploy-rs:
$ deploy .#app-1 .#app-2 .#app-3
```

The `deploy` script here forwards `deploy web-1 --skip-checks` and
friends untouched; anything more elaborate you can drop into
`deploy` directly.

## When magic rollback bites you

Some changes are *supposed* to break the probe -- moving sshd to a
non-standard port, changing the interface deploy-rs SSHes to,
enabling a firewall rule that blocks the probe. Those need
`--no-magic-rollback`:

```console
$ deploy web-1 -- --no-magic-rollback
```

Use with care. If the change breaks something, you have to console
in or `install-host --force` to recover.

## Documenting operational state

Nothing in the repo forces you to, but two conventions save you
later:

- A `CHANGELOG.md` in the fleet repo, one line per notable deploy.
- Commit messages that say *why*, not just *what*. `git log` on the
  fleet repo is the audit trail.

## What next

You know the routine. [Writing host-specific modules](writing-host-modules.md) covers writing your own
host-specific modules -- adding a real service, a disk layout,
overriding one of the nixops defaults for a single host. [Troubleshooting](troubleshooting.md)
is the failure-mode manual.

Next: [Writing host-specific modules](writing-host-modules.md)

## References for this chapter

- [Zero to Nix -- Nix in production](https://zero-to-nix.com/concepts/nix-in-production)
- [NixOS Manual -- upgrading](https://nixos.org/manual/nixos/stable/#sec-upgrading)
- [NixOS Manual -- rollback](https://nixos.org/manual/nixos/stable/#sec-rollback)
- [NixOS Wiki -- Cheatsheet](https://wiki.nixos.org/wiki/Cheatsheet)
  -- one page of command reminders; print and tape to your desk.
- [NixOS Discourse -- ops-related discussion](https://discourse.nixos.org/c/dev/deploy/50)
