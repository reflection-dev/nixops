<!--
Thanks for the PR! Please fill in the sections below so a reviewer can pick it up
without needing to guess intent. Delete sections that do not apply.
-->

## What

<!-- One or two sentences on what this PR changes. -->

## Why

<!-- The problem it solves, or the itch it scratches. Link an issue if there is one. -->

## How

<!-- The high-level shape of the change. Mention any new module toggles, script
     flags, or breaking changes to the flake outputs. -->

## Checklist

- [ ] Follows [Conventional Commits](https://www.conventionalcommits.org/)
      (`feat(module): ...`, `fix: ...`, `docs: ...`, ...).
- [ ] `nix flake check` passes locally.
- [ ] `nix fmt` has been run.
- [ ] If a new base module was added, it exposes a `nixops.<name>.enable`
      toggle with a sane default and is registered in `modules/default.nix`.
- [ ] If a script was changed, it stays gum-driven (no plain `read`) and
      confirms every destructive action.
- [ ] No private key material is read, copied, or logged by new code
      (see [SECURITY.md](../SECURITY.md)).
- [ ] Tutorial pages under `docs/` stay strict-ASCII (no em-dashes, curly
      quotes, or ellipses).
- [ ] Screenshots / terminal recordings attached if the change is
      user-facing.
