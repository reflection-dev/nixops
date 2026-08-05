---
time: "45 minutes -- longer if you follow along in `nix repl`"
---
# 03 -- The Nix language

> **Prerequisite:** [Install Nix and enable flakes](install-nix.md) (you have a working `nix` command).
>
> **Outcome:** you can read every construct in this repo's `flake.nix`, `lib/*.nix`, and `modules/*.nix` without needing a lookup.

The Nix language is small: a pure, lazy, functional expression
language whose only job is to evaluate down to values -- attribute
sets, strings, lists, and derivations (build recipes). There are no
statements, no loops, no assignment. Everything is an expression.

This chapter teaches only what you need to operate this repo.
For the complete reference, see [nix.dev -- Nix language
basics](https://nix.dev/tutorials/nix-language) and the [Nix
Reference Manual -- Language](https://nix.dev/manual/nix/stable/language/).

## Follow along

Start the REPL in a shell so you can type each example:

```console
$ nix repl
Welcome to Nix. Type :? for help.
nix-repl>
```

Exit with `:q`. Reload with `:r`.

## Values

Nix has the values you would expect and nothing exotic:

```nix
nix-repl> 42
42

nix-repl> 3.14
3.14

nix-repl> true
true

nix-repl> null
null

nix-repl> "hello"
"hello"

nix-repl> [ 1 2 3 ]        # lists are space-separated, no commas
[ 1 2 3 ]

nix-repl> { a = 1; b = 2; } # attribute sets: keys, `=`, values, `;`
{ a = 1; b = 2; }
```

Two things to internalise now:

- **Lists use spaces, not commas.** `[ 1 2 3 ]`, not `[ 1, 2, 3 ]`.
- **Attribute sets end each binding with `;`.** Every one. Missing
  semicolons are the most common typo.

## Strings

Two forms:

```nix
nix-repl> "single-line string"
"single-line string"

nix-repl> ''
    multi-line string
    common indentation is stripped
  ''
"multi-line string\ncommon indentation is stripped\n"
```

String interpolation uses `${...}`:

```nix
nix-repl> let name = "web-1"; in "hello, ${name}"
"hello, web-1"
```

Inside `''...''` you use `''${...}` for a literal `${` -- you will
rarely need this.

## Attribute sets

The workhorse type. Keyed, like a JSON object, but the keys are
Nix identifiers (or quoted strings for anything else):

```nix
nix-repl> { hostname = "web-1"; ip = "1.2.3.4"; }
{ hostname = "web-1"; ip = "1.2.3.4"; }
```

Access with `.`:

```nix
nix-repl> let h = { name = "web"; ip = "1.2.3.4"; }; in h.ip
"1.2.3.4"
```

Nested paths work as attribute paths:

```nix
nix-repl> { services.nginx.enable = true; }
{ services = { nginx = { enable = true; }; }; }
```

Those two forms are equivalent. `services.nginx.enable = true;` is
sugar for the nested set. This is *the* pattern in NixOS modules.

Merge two sets with `//`:

```nix
nix-repl> { a = 1; } // { b = 2; }
{ a = 1; b = 2; }

nix-repl> { a = 1; } // { a = 2; }    # right side wins
{ a = 2; }
```

## `let ... in`

Define local bindings; return the expression after `in`.

```nix
nix-repl> let
            name = "web-1";
            ip = "1.2.3.4";
          in
            "${name} is at ${ip}"
"web-1 is at 1.2.3.4"
```

You will see `let ... in { ... }` at the top of most files:

```nix
{ nixpkgs, sops-nix, self }:      # arguments (see functions below)
{ hosts, sshKeys ? [ ] }:
let
  defaultSystem = "x86_64-linux";
in
  builtins.mapAttrs mkOne hosts
```

## Functions

A function takes one argument and returns an expression. The
`arg: body` form:

```nix
nix-repl> (x: x + 1) 3
4
```

Multiple arguments are curried:

```nix
nix-repl> (x: y: x + y) 2 3
5
```

But the more common pattern in Nix code is a function that takes a
single **attribute set** with named fields. This is how modules,
flakes, and library functions look:

```nix
nix-repl> ({ x, y }: x + y) { x = 2; y = 3; }
5
```

Optional arguments have defaults with `?`:

```nix
nix-repl> ({ x, y ? 10 }: x + y) { x = 2; }
12
```

The `...` allows extra fields that are ignored:

```nix
nix-repl> ({ x, ... }: x) { x = 2; y = 3; z = 4; }
2
```

Every NixOS module you will write starts with `{ config, lib, pkgs,
... }:` -- that is a function taking a set with those three fields
(and ignoring any others the module system passes in).

Look at `modules/ssh.nix`:

```nix
{ config, lib, ... }: let
  cfg = config.nixops.ssh;
in {
  options.nixops.ssh = { ... };
  config = lib.mkIf cfg.enable { ... };
}
```

That is: a function taking an attribute set with `config` and `lib`
(and possibly others), that returns an attribute set with `options`
and `config` fields.

## `with`

`with foo; expr` brings the attributes of `foo` into scope in
`expr`. You will see this in package lists:

```nix
environment.systemPackages = with pkgs; [
  git vim htop
];
```

Equivalent to `[ pkgs.git pkgs.vim pkgs.htop ]`. Convenient; use
sparingly (large `with` scopes hide where names come from).

## `import`

`import ./file.nix` reads the file and evaluates its expression. If
the file's top-level expression is a function, you can call it in
one go:

```nix
import ./hosts.nix                        # returns the value from hosts.nix
import ./lib/mkDeploy.nix { inherit deploy-rs; }   # imports then calls
```

Both are used across this repo.

## Conditionals

`if ... then ... else ...` (all three branches required):

```nix
nix-repl> if 3 > 2 then "yes" else "no"
"yes"
```

## `inherit`

Shorthand for copying names from an enclosing scope into an
attribute set:

```nix
nix-repl> let a = 1; b = 2; in { inherit a b; }
{ a = 1; b = 2; }
```

Equivalent to `{ a = a; b = b; }`. Very common in flakes.

`inherit (foo) a b;` pulls `foo.a` and `foo.b`:

```nix
nix-repl> let s = { a = 1; b = 2; c = 3; }; in { inherit (s) a b; }
{ a = 1; b = 2; }
```

## Common library functions

`nixpkgs.lib` gives you the standard toolbox. A tour of the ones you
will meet in this repo:

- `lib.mkOption { type; default; description; }` -- declare an
  option in a module. Used in every `modules/*.nix`.
- `lib.mkIf cond attrs` -- include `attrs` in the merged config only
  if `cond` is true. Every module uses `lib.mkIf cfg.enable { ... }`
  to make itself opt-outable.
- `lib.mkDefault value` / `lib.mkForce value` / `lib.mkOverride
  prio value` -- set option values with a specific merge priority.
  Higher priority beats lower; forcing wins over anything a downstream
  module tries to set.
- `lib.types.bool` / `.str` / `.port` / `.int` / `.package` /
  `.listOf t` / `.attrsOf t` / `.nullOr t` -- option type checkers.
- `lib.mapAttrs f attrs` -- apply `f name value` to every entry.
  `lib/mkNixosConfigs.nix` uses `builtins.mapAttrs mkOne hosts` to
  turn each inventory entry into a NixOS config.
- `lib.mapAttrsToList f attrs` -- like `mapAttrs` but returns a list.
  Used in `lib/mkDevShell.nix` to build the ssh config lines.
- `lib.genAttrs [ "x" "y" ] f` -- build `{ x = f "x"; y = f "y"; }`.
  The flake's `apps` output uses this to declare per-system apps.

`builtins.*` are the primitives baked into Nix itself
(`readFile`, `mapAttrs`, `removeAttrs`, `concatStringsSep`,
`toString`, ...). `lib.*` are the higher-level helpers Nixpkgs
provides.

Complete builtins reference: [Nix Reference Manual -- built-in
functions](https://nix.dev/manual/nix/stable/language/builtins).

Nixpkgs `lib` search: [noogle.dev](https://noogle.dev/) -- essential
tool once you start writing modules.

## Lazy evaluation

Nix only evaluates what it needs. This has one visible consequence
you should know about: **the order of bindings in a `let` or an
attribute set does not matter.** You can refer to `y` from `x` even
if `y` is defined below `x`. Bindings do have to eventually resolve
without cycles, but the order of appearance is free.

## Putting it together: read this repo's `lib/mkDeploy.nix`

```nix
{ deploy-rs }:
nixosConfigurations:
builtins.mapAttrs (_name: nixosConfig: {
  hostname = nixosConfig.config.nixops.host.ip;
  sshUser  = "root";
  profiles.system = {
    user = "root";
    path = deploy-rs.lib.${nixosConfig.pkgs.stdenv.hostPlatform.system}.activate.nixos
      nixosConfig;
  };
}) nixosConfigurations
```

Read left-to-right:

1. Function taking `{ deploy-rs }` -> function taking
   `nixosConfigurations` -> the body (two nested functions).
2. Body: `builtins.mapAttrs` applied to a callback and to
   `nixosConfigurations` -- iterate every name/config pair.
3. Callback: `(_name: nixosConfig: { ... })` -- ignore the name,
   take the config, produce a deploy node record.
4. Inside the record: `hostname` from the host's declared IP,
   `sshUser = "root"`, and the activation script that `deploy-rs`
   understands.

Every construct in the file is one from this chapter.

## What next

- [Flakes](flakes.md) introduces flakes -- the packaging that lets Nix
  reference other repositories reproducibly.
- [NixOS and the module system](nixos-and-modules.md) introduces the NixOS module system -- the vocabulary
  behind `options` / `config` / `imports`.

If any of the above still feels shaky, spend 20 minutes in `nix
repl` typing the examples. Reading Nix without having typed it is
like reading Python from a screenshot; you will re-learn everything
the first time you type it.

Next: [Flakes](flakes.md)

## References for this chapter

- [nix.dev -- Nix language basics](https://nix.dev/tutorials/nix-language)
- [Nix Reference Manual -- Language](https://nix.dev/manual/nix/stable/language/)
- [Nix Reference Manual -- built-in functions](https://nix.dev/manual/nix/stable/language/builtins)
- [noogle.dev](https://noogle.dev/) -- searchable index of every
  function in `builtins` and Nixpkgs `lib`.
- [Nix Pills, chapters 3-6](https://nixos.org/guides/nix-pills/basics-of-language.html)
  -- deeper dive, if you want to understand the evaluator itself.
