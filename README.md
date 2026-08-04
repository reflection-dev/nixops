# nixops

Generic NixOS fleet base — inventory-driven modules, `deploy-rs` + `sops-nix`
wiring, `nixos-anywhere` bootstrap, and an ops devShell.

Scaffolded into an instance repo with:

```
nix run github:reflection-dev/nixops -- new my-fleet
```

Not for AI-specific setups — that layer lives in
[reflection-dev/castle](https://github.com/reflection-dev/castle), which
will build on top of nixops.

Work in progress. Public surface (flake outputs, devShell commands, wizard)
is defined across the follow-up commits.
