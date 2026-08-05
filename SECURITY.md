# Security Policy

## Supported versions

`nixops` is released from `master`; fixes land there and there is no separate
maintenance branch. Consumers pin the flake to a specific revision, so security
fixes are applied by bumping that revision.

## Reporting a vulnerability

Please report security issues **privately**:

- Preferred: GitHub's **"Report a vulnerability"** button under the repository's
  *Security* tab, or
- Email **andy@reflection.dev**.

Do not open a public issue for an undisclosed vulnerability. Include steps to
reproduce and the impact; you will get an acknowledgement within a few days.

## Scope

In-scope: the modules, scripts, and library functions this repo publishes
(`modules/*.nix`, `lib/*.nix`, `scripts/*.sh`, the `templates/default`
instance template, and the `opsvm` package).

Out of scope: vulnerabilities in upstream projects (`nixos-anywhere`,
`deploy-rs`, `sops-nix`, `nixpkgs`) unless triggered by an unsafe default in
this repo. Please report those to their upstream maintainers.

## Handling secrets

`nixops` orchestrates `sops-nix` and `nixos-anywhere`, both of which touch
sensitive material (age keys, SSH host keys, secrets from `sops.secrets.*`).
Two rules the code (and any contribution) must uphold:

- **Never read or copy private key material** without the operator explicitly
  requesting it. The devShell scripts touch only public parts (age recipients
  derived via `ssh-to-age`) and never dump the contents of
  `~/.config/sops/age/keys.txt` or `~/.ssh/id_*` to logs or the screen.
- **Host key material is single-use.** `install-host` generates the target's
  `ssh_host_ed25519_key` locally, ships it to the target via
  `nixos-anywhere --extra-files`, and removes the local copy on success. Any
  change that lengthens that window (or persists the key on the operator
  machine) is a security regression.

If you find behavior that violates either rule, please report it via the
channels above.
