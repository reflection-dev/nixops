# Contributing to nixops

Thanks for your interest! `nixops` is a generic NixOS fleet base -- inventory,
modules, and the plumbing to install and deploy servers with `nixos-anywhere`,
`sops-nix`, and `deploy-rs`. Bug reports, module improvements, tutorial fixes,
and PRs are all welcome.

## Development setup

You need [Nix](https://nixos.org/download.html) with flakes enabled. On any
Linux/macOS workstation:

```
git clone https://github.com/reflection-dev/nixops
cd nixops
nix flake check          # evaluates the flake and every nixosConfiguration
nix develop              # optional; drops into a shell with fmt/lint tools
```

To exercise the tool end-to-end against a throwaway VM (no host secrets
touched):

```
nix run .#opsvm -- scratch
```

The `opsvm` package builds a NixOS QEMU workstation with the full operator
toolchain pre-installed; see [docs/operating/opsvm.md](docs/operating/opsvm.md).

## Repo layout

- `flake.nix` -- inputs, outputs (`nixosModules`, `lib`, `packages`,
  `apps`, `templates`, `devShells`).
- `modules/*.nix` -- the base NixOS modules (`ssh`, `sops`, `users`,
  `firewall`, `nix-defaults`, `ops-workstation`). Every module is
  toggle-driven via `nixops.<name>.enable`.
- `lib/*.nix` -- pure helpers used by instances (`mkNixosConfigs`,
  `mkDeploy`, `mkDevShell`).
- `scripts/*.sh` -- the interactive devShell commands (`add-host`,
  `install-host`, `deploy`, `update-secrets`, `new`, `opsvm-launch`).
- `templates/default/` -- the instance scaffold produced by
  `nix flake init -t` and by the `new` wizard.
- `docs/` -- the zero-to-fleet tutorial (see
  [docs/overview/index.md](docs/overview/index.md)).

## Making changes

- **Keep the flake reproducible.** Pin new inputs, follow the existing
  `inputs.<x>.inputs.nixpkgs.follows = "nixpkgs"` pattern, and run
  `nix flake update <input>` in its own commit.
- **New base modules** go in `modules/` and must be opt-in-safe:
  expose a `nixops.<name>.enable` toggle with a sensible default, and
  register the module in `modules/default.nix`.
- **Scripts** run in the operator devShell; keep them POSIX-friendly
  (`bash`) and use `gum` for any prompt -- do not fall back to plain
  `read`. Every destructive path (files rewritten, remote install)
  must confirm before acting.
- **Never read or copy private key material.** The scripts touch only
  public parts (age recipients derived via `ssh-to-age`, generated host
  keys shipped once via `--extra-files` and removed on success). See
  [SECURITY.md](SECURITY.md).
- **Tutorial changes** live under `docs/<section>/<page>.md`. Preserve
  the strict-ASCII convention (no em-dashes, curly quotes, ellipses --
  `--` means two hyphens) and the existing frontmatter format; every
  chapter is listed in `docs/_meta.json`.
- **Format Nix** with `nix fmt` before committing.
- **Verify** with `nix flake check` before opening a PR. CI runs the
  same check.

## Commits and pull requests

- Follow [Conventional Commits](https://www.conventionalcommits.org/):
  `feat(opsvm): ...`, `fix(sops): ...`, `docs: ...`, `chore: ...`.
- Branch from `master`, keep each PR focused, and explain **why** the
  change is needed (the diff shows the what).
- The [PR template](.github/pull_request_template.md) has the checklist.
- Signed commits are preferred; the codebase is signed as
  `Andy <andy@reflection.dev>`.

## Reporting issues

Open an issue with one of the [templates](.github/ISSUE_TEMPLATE/). For
anything security-related, follow [SECURITY.md](SECURITY.md) instead of
filing a public issue.

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE) and to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).
