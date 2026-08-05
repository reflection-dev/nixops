---
time: "40 minutes"
---
# Secrets with sops-nix

> **Prerequisite:** [NixOS and the module system](../foundations/nixos-and-modules.md).
>
> **Outcome:** you understand what `.sops.yaml`, an age key, and `sops.secrets.*` are; you know how a secret gets from your laptop to `/run/secrets/<name>` on a NixOS host; you know how this repo's `install-host` and `update-secrets` scripts orchestrate the flow.

Managing secrets on Nix is a solved problem, and `sops-nix` is the
solution this fleet base picks. If you have used HashiCorp Vault,
Ansible Vault, or `age` on its own, the mental model is not far
off. If not, this chapter builds it from scratch.

## Why this problem is hard

You have secrets: an API token, a TLS private key, a database
password. You want:

1. to keep them in git alongside the rest of your infrastructure
   (so history and review work), but
2. never to have them in plaintext there, and
3. to have them appear as *plaintext files* on the target host so
   that services can read them, and
4. to control *which* host can decrypt *which* file (a compromised
   web server should not be able to decrypt the database node's
   secrets).

`sops` (Mozilla's [Secrets OPerationS](https://github.com/getsops/sops))
provides (1) and (2). `age` is the modern encryption format sops
uses (small keys, no PKI ceremony). `sops-nix` glues sops into
NixOS's module system to give you (3) and (4).

## The 90-second picture

```text
                       .sops.yaml
                       (recipients + rules)
                             |
             sops encrypts   v
   plaintext values ----> secrets/<host>.yaml   ---- committed to git
                             |
                             |  (nixos-anywhere ships host's
                             |   age key at first install;
                             |   sops-nix reads it on boot)
                             v
                       /run/secrets/<name>
                       (plaintext, on the target host, root-only)
                             |
                             v
                   consumed by services
                   (e.g. systemd EnvironmentFile,
                    sshd, wireguard, ...)
```

## `age`, briefly

`age` is a modern file-encryption tool built by Filippo Valsorda.
Keys are short strings starting with `AGE-SECRET-KEY-` (private) or
`age1` (public / recipient). No PKI, no key servers, no expirations
-- you generate a key, share the public half, keep the private
half.

```console
$ age-keygen -o ~/.config/sops/age/keys.txt
Public key: age1abc123...
```

The public key ("recipient") is what you hand out. The private key
lives in that file; nothing else needs to know it.

**Never `cat` or read the private-key file directly.** To display
the public key from an existing private-key file:

```console
$ age-keygen -y ~/.config/sops/age/keys.txt
age1abc123...
```

`age-keygen -y` derives the public part without echoing the private
key. This repo's scripts and this tutorial follow that rule; you
should too.

Reference: [age(1)](https://github.com/FiloSottile/age).

## Deriving age from SSH host keys

Here is a clever trick this repo relies on: NixOS servers already
have an ed25519 host key
(`/etc/ssh/ssh_host_ed25519_key`) generated at install time. That
key is mathematically compatible with age, and the tool
[`ssh-to-age`](https://github.com/Mic92/ssh-to-age) converts it to
an age recipient in one line:

```console
$ ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub
age1def456...
```

That means every NixOS host can be an age recipient *without any
extra key material*: sops-nix decrypts at boot using the SSH host
key that is already there. The `modules/sops.nix` module says
exactly that:

```nix
sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
```

`install-host` bootstraps this by generating the host's ed25519 key
locally, deriving its age recipient, adding it to `.sops.yaml`, and
shipping the private key to the target as `--extra-files` during
`nixos-anywhere`. That first-boot has the key in place, so
`sops-nix` can decrypt from the very first boot.

## `.sops.yaml`

The rulebook. Two sections:

- `keys:` -- a list of anchor-named recipients you can reference by
  alias further down.
- `creation_rules:` -- for each path pattern, which recipients can
  decrypt files created there.

The scaffold from `templates/default/.sops.yaml`:

```yaml
keys:
  - &admin_you   age1REPLACE_WITH_YOUR_LAPTOP_AGE_PUBLIC_KEY

creation_rules: []
```

After `install-host web-1` runs, the file grows into something like:

```yaml
keys:
  - &admin_you   age1youdefinitely...
  - &web-1       age1web1derivedfromitssshkey...

creation_rules:
  - path_regex: secrets/web-1\.yaml$
    key_groups:
      - age: [ *admin_you, *web-1 ]
```

Read: "files matching `secrets/web-1.yaml` are encrypted for the
admin recipient *and* for web-1's own age recipient". You (on your
laptop) can decrypt because your admin key is a recipient; web-1
can decrypt at boot because it holds the private half of its age
identity.

If you later add a database node, `install-host db-1` appends a
similar block with `secrets/db-1\.yaml` and web-1 will *not* be a
recipient there. Least-privilege is the default.

Reference: [getsops/sops -- README](https://github.com/getsops/sops)
and [Mic92/sops-nix -- README](https://github.com/Mic92/sops-nix).

## Encrypted files

An encrypted `secrets/web-1.yaml` looks like:

```yaml
# somewhat trimmed
db_password: ENC[AES256_GCM,data:...,iv:...,tag:...]
api_token:   ENC[AES256_GCM,...]
sops:
  age:
    - recipient: age1youdefinitely...
      enc: |
        -----BEGIN AGE ENCRYPTED FILE-----
        ...
        -----END AGE ENCRYPTED FILE-----
    - recipient: age1web1derivedfromitssshkey...
      enc: |
        ...
  lastmodified: ...
  mac: ENC[...]
```

- Each **secret value** is encrypted with a randomly-generated data
  key.
- The **data key** is then wrapped for every recipient in the
  `sops:` block.

To decrypt as an admin from your laptop:

```console
$ sops secrets/web-1.yaml
```

You get an interactive editor with the plaintext. Save and exit;
sops re-encrypts. Adding, editing, or removing individual entries
this way is safe.

## Adding secrets in this repo

Two workflows:

- **Interactive** (through `update-secrets`, driven by what the
  NixOS config declares -- see below). This is the recommended
  path.
- **Manual** with `sops secrets/<host>.yaml`. Works fine; just be
  sure the file already exists and that `.sops.yaml` has a
  matching `creation_rule`.

## `sops.secrets.*` -- the NixOS-side view

On the NixOS side, sops-nix gives you a module option:

```nix
sops.secrets.db_password = {
  sopsFile = ./secrets/web-1.yaml;
  owner    = "myservice";
  group    = "myservice";
  mode     = "0400";
};
```

At boot, sops-nix will:

1. read `/etc/ssh/ssh_host_ed25519_key`;
2. decrypt every `sops.secrets.<key>` value from the given file;
3. write plaintext to `/run/secrets/<key>` with the requested
   owner, group, and mode.

Your service module then references the plaintext path:

```nix
systemd.services.myservice.serviceConfig.EnvironmentFile =
  config.sops.secrets.db_password.path;
```

`config.sops.secrets.db_password.path` evaluates to
`/run/secrets/db_password`. Never hard-code the path yourself; let
sops-nix give you the option value.

Full option reference: [sops-nix README -- NixOS options](https://github.com/Mic92/sops-nix#usage-example).

## How `update-secrets` works

Every time you (or `install-host`) needs to fill in missing
secrets, `update-secrets [host]` in the devShell does the
inventory-driven equivalent of running `sops` by hand. From the top
of [`scripts/update-secrets.sh`](../scripts/update-secrets.sh):

```bash
# Reads the expected keys from
#   .#nixosConfigurations.<name>.config.sops.secrets
# and prompts (via gum) for any that are not yet set in
# secrets/<name>.yaml. Existing values are left untouched.
```

The clever part: the list of "secrets this host needs" is not a
separate config file. It is *the same* `sops.secrets.*` attribute
you already declared in a NixOS module. `update-secrets` reads it
with `nix eval` and prompts you for whichever ones do not yet exist
in the encrypted file.

The consequence: you never have a mismatch between "secrets the
system expects" and "secrets the yaml has". If you add a new
`sops.secrets.foo` to a module and run `deploy`, it will fail at
boot; but running `update-secrets` first will notice `foo` is
missing and prompt you to fill it.

## Rotating a recipient

Two cases:

- **A host's age recipient changed** (rare -- would mean
  regenerating its SSH host key). Re-run `install-host --force`
  after updating `.sops.yaml`, or run `sops updatekeys
  secrets/<host>.yaml` yourself.
- **An admin key was added or removed.** Edit `.sops.yaml`, then
  `sops updatekeys secrets/*.yaml`. Every file gets re-encrypted
  for the new recipient set. Commit.

`install-host` does the `updatekeys` step for you when it modifies
`.sops.yaml`.

Reference: [getsops/sops -- Adding and removing keys](https://github.com/getsops/sops#adding-and-removing-keys).

## Common gotchas

- **`sops-nix` fails at boot with "no age key found"**. The host's
  SSH host key is missing or does not match the recipient in
  `.sops.yaml`. Check `ssh-to-age -i
  /etc/ssh/ssh_host_ed25519_key.pub` against what `.sops.yaml`
  lists.
- **"Recipient not found in creation rule"**. You created a new
  encrypted file whose path does not match any `creation_rules`
  path_regex. Add a rule to `.sops.yaml`.
- **"Cannot decrypt on the laptop"**. Your `~/.config/sops/age/keys.txt`
  is either missing or holds a different key than `.sops.yaml`'s
  admin recipient expects. Fix the recipient (and `sops updatekeys`
  every file) or fix which key you use.
- **Committing an unencrypted secrets file**. Never; use `git diff`
  before commits. `sops` shows the encrypted form; if the file has
  raw plaintext values, `sops` was skipped somewhere.

## Alternative secret backends

sops-nix also supports GnuPG, AWS KMS, GCP KMS, Azure Key Vault,
and HashiCorp Vault -- you list them in `.sops.yaml` alongside age.
This tutorial sticks to age because it is the simplest, needs no
external service, and works for the "small fleet, personal admin
laptop" case this repo targets.

For a cluster with strict compliance where the encryption key must
live in an HSM, swap age for KMS in `.sops.yaml`; the NixOS side
does not change. Details: [getsops/sops -- KMS](https://github.com/getsops/sops#usage).

## What next

You know the secret pipeline. Next is the first-boot pipeline:
how a bare Linux target becomes a NixOS host without a rescue image.

Next: [Remote install with nixos-anywhere](nixos-anywhere.md)

## References for this chapter

- [Mic92/sops-nix](https://github.com/Mic92/sops-nix) -- the
  canonical source. Read the README end-to-end at some point.
- [getsops/sops](https://github.com/getsops/sops) -- upstream sops
  CLI.
- [FiloSottile/age](https://github.com/FiloSottile/age) -- age
  format and CLI.
- [Mic92/ssh-to-age](https://github.com/Mic92/ssh-to-age) -- the
  converter this repo uses.
- [Zero to Nix -- concepts](https://zero-to-nix.com/concepts/) --
  ecosystem context.
- [NixOS Wiki -- Comparison of secret managing schemes](https://wiki.nixos.org/wiki/Comparison_of_secret_managing_schemes)
  -- if you want to know why we picked sops over
  agenix/git-crypt/etc.
- [NixOS Discourse -- "secrets" tag](https://discourse.nixos.org/tag/secrets)
  -- ongoing community discussions.
