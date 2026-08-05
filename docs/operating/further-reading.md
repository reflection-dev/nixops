# 14 -- Further reading

> **Prerequisite:** [Chapter 13](troubleshooting.md), or just an appetite.
>
> **Outcome:** you know where to go for depth in every direction the tutorial only touched on.

This is a curated list. Everything here is either canonical
(official docs) or widely-endorsed by the community. No half-
finished blog posts, no dead links.

Bookmark, do not memorise. Return here whenever you catch yourself
thinking "there should be a good source for this".

## Start-here hubs

- **[nix.dev](https://nix.dev/)** -- the official modern
  documentation site. If you are unsure where a topic lives, start
  here. Maintained by the NixOS Foundation Documentation Team.
- **[Zero to Nix](https://zero-to-nix.com/)** -- Determinate
  Systems' friendly, opinionated intro. Great complement to this
  tutorial; often clearer on concepts, less on operations.
- **[NixOS website](https://nixos.org/)** -- the landing page.
  Points at every downstream resource.
- **[NixOS learn page](https://nixos.org/learn.html)** -- the
  aggregator of official learning material.

## Manuals (authoritative)

Every Nix / NixOS / Nixpkgs question has an answer here. They are
dense; use search.

- **[Nix Reference Manual](https://nix.dev/manual/nix/stable/)**
  -- the language, the CLI, the store, everything the `nix` binary
  can do.
- **[NixOS Manual](https://nixos.org/manual/nixos/stable/)**
  -- installing, configuring, and administering NixOS. Sections
  worth flagging:
  - [Configuration Options](https://nixos.org/manual/nixos/stable/options.html)
    -- every option NixOS ships.
  - [Writing Modules](https://nixos.org/manual/nixos/stable/#sec-writing-modules)
  - [NixOS tests](https://nixos.org/manual/nixos/stable/#sec-nixos-tests)
    -- integration tests in VM sandboxes; incredibly useful once
    you write serious modules.
- **[Nixpkgs Manual](https://nixos.org/manual/nixpkgs/stable/)**
  -- how the package collection is structured, how to write a
  derivation, overlays, `mkDerivation`, `stdenv`, everything
  package-side.

## Search tools

- **[search.nixos.org/packages](https://search.nixos.org/packages)**
  -- every package in nixpkgs, by name.
- **[search.nixos.org/options](https://search.nixos.org/options)**
  -- every NixOS option. Bookmark it.
- **[noogle.dev](https://noogle.dev/)** -- every function in
  `builtins` and Nixpkgs `lib`. Essential once you start writing
  modules.
- **[my-nixos.com](https://my-nixos.com/)** -- alternate search UI
  covering options + packages + several third-party module sets.

## Community-maintained knowledge

- **[NixOS Wiki](https://wiki.nixos.org/)** -- the modern wiki,
  actively maintained. Great for "how do I do X" recipes and
  ecosystem overviews. Older `nixos.wiki` redirects here.
- **[NixOS Discourse](https://discourse.nixos.org/)** -- the
  primary forum. Search first, ask second. Categories worth
  browsing:
  - [Learn](https://discourse.nixos.org/c/learn/9) -- newcomer
    questions.
  - [Deploy](https://discourse.nixos.org/c/dev/deploy/50) --
    deploy-rs, nixops4, Colmena, etc.
  - [News + Announcements](https://discourse.nixos.org/c/announcements/8)
    -- release notes, tool announcements.

## Chat

- **[NixOS Matrix rooms](https://matrix.to/#/#community:nixos.org)** --
  the main chat platform.
  - `#nixos:nixos.org` -- general.
  - `#nixos-help:nixos.org` -- how-do-I questions.
  - `#nix-dev:nixos.org` -- development.
  - Language, tool, and topic subrooms all live under
    `#nixos.org` as well.
- **NixOS on Reddit** -- [r/NixOS](https://reddit.com/r/NixOS).
  Lower signal than Discourse but useful for community pulse.

## Books

- **[Nix Pills](https://nixos.org/guides/nix-pills/)** -- Luca
  Bruno's series that reconstructs Nix from first principles. Long,
  worth every page. Chapters 1-6 are the language; 7-20 are
  derivations and packaging; the rest are advanced.
- **[nix.dev tutorials](https://nix.dev/tutorials/)** -- the
  Foundation's guided tutorials. Complements this doc.
- **[Xe Iaso: NixOS series](https://xeiaso.net/tags/nixos)** --
  well-written blog series. The flake tutorials are worth reading
  after Chapter 4.

## Deploy tools

If you outgrow `deploy-rs` (or want to compare):

- **[deploy-rs](https://github.com/serokell/deploy-rs)** -- what
  this repo uses.
- **[Colmena](https://github.com/zhaofengli/colmena)** --
  well-maintained alternative; declarative fleet layout inside the
  flake. [Docs](https://colmena.cli.rs/).
- **[NixOps4](https://github.com/nixops4/nixops4)** -- the
  official next-gen deploy tool from the NixOS Foundation. Still
  maturing.
- **[disnix](https://github.com/svanderburg/disnix)** -- service-
  level distributed deployment. Niche.

Wiki comparison: [NixOS Wiki -- Deployment tools](https://wiki.nixos.org/wiki/Comparison_of_deployment_tools).

## Secrets

- **[Mic92/sops-nix](https://github.com/Mic92/sops-nix)** -- what
  this repo uses. Read the README end-to-end.
- **[ryantm/agenix](https://github.com/ryantm/agenix)** --
  alternative built around age. Simpler than sops-nix, no rules-
  file complexity, but no KMS/GPG support.
- **[HashiCorp Vault + Nixpkgs](https://nixos.org/manual/nixos/stable/#module-services-vault)**
  -- if you already have Vault, NixOS talks to it.
- **[NixOS Wiki -- Comparison of secret managing schemes](https://wiki.nixos.org/wiki/Comparison_of_secret_managing_schemes)**
  -- rational overview of trade-offs.

## Disk layout

- **[nix-community/disko](https://github.com/nix-community/disko)** --
  the standard tool. Examples directory has recipes for GPT+ext4,
  LUKS, ZFS, btrfs, LVM, RAID, and combinations.
- **[NixOS Wiki -- Disko](https://wiki.nixos.org/wiki/Disko)**.
- **[NixOS Wiki -- ZFS](https://wiki.nixos.org/wiki/ZFS)** -- if
  you use ZFS on any host, read this once before you commit to a
  layout.

## Testing

- **[NixOS tests](https://nixos.org/manual/nixos/stable/#sec-nixos-tests)** --
  the integration-test framework. You can spin up whole networks
  of NixOS VMs, run Python assertions against them, and CI the
  results. Best-in-class; nothing outside Nix has an equivalent.
- **[nixt](https://github.com/nix-community/nixt)** -- unit-test
  framework for Nix expressions.

## Ops adjacencies

Not part of this tutorial, but you will meet them:

- **[nix-darwin](https://github.com/LnL7/nix-darwin)** -- run
  "NixOS-style" module system on macOS. If your ops laptops are
  Macs, this is how you version-control them.
- **[home-manager](https://github.com/nix-community/home-manager)** --
  manage user dotfiles / user-scope packages declaratively.
- **[nix-community/nixvim](https://github.com/nix-community/nixvim)** --
  configure Neovim declaratively.
- **[cachix](https://www.cachix.org/)** -- run your own binary
  cache (or point at community-provided ones).
- **[hydra](https://github.com/NixOS/hydra)** -- the CI system
  Nixpkgs itself uses. Overkill for a small fleet; useful once you
  want to prebuild your own store paths.
- **[flake-parts](https://flake.parts/)** -- module-system-style
  organisation for flakes themselves. Nice once your flake grows.

## Talks and videos

- **[NixCon](https://www.youtube.com/@NixCon)** -- annual
  conference; recordings on YouTube. Search for talks by year for
  recent work.
- **[Nixpkgs Architecture Team meetings](https://discourse.nixos.org/c/dev/foundation/54)** --
  archive of design discussions; open community.

## Reflection-dev repos

- **[reflection-dev/nixops](https://github.com/reflection-dev/nixops)** --
  this repo.
- **[reflection-dev/castle](https://github.com/reflection-dev/castle)** --
  AI-agent-specific NixOS layer, built on top of nixops. Not
  needed for this tutorial; relevant if you want AI-agent
  workflows.

## And when you get stuck

The order that usually works fastest, in decreasing likelihood of a
hit:

1. Search [search.nixos.org/options](https://search.nixos.org/options)
   (for a NixOS option) or [/packages](https://search.nixos.org/packages)
   (for a package name).
2. Search [NixOS Wiki](https://wiki.nixos.org/) for the tool or
   error.
3. Search [NixOS Discourse](https://discourse.nixos.org/) for the
   error message verbatim.
4. Read the manual chapter for the module in question.
5. Ask in [`#nixos-help:nixos.org`](https://matrix.to/#/#nixos-help:nixos.org)
   or on Discourse.
6. If it looks like a bug, open an issue in the relevant repo.

Welcome to Nix. It repays every hour you spend learning it, and
the community rewards specific, well-formulated questions
generously.
