# add-host [<name>]
#
# Interactive: prompts for the target IP, picks a disk layout preset (or
# leaves disko.nix out for hand-writing), scaffolds hosts/<name>/ with a
# default.nix and a placeholder hardware-configuration.nix, and appends an
# entry to hosts.nix keyed on <name>.
#
# If <name> is not given as an argument, prompts for it.
#
# The placeholder hardware-configuration.nix is overwritten on first
# `install-host <name>` via nixos-anywhere's --generate-hardware-config.
#
# Deliberately does not touch .sops.yaml -- that happens on `install-host`
# when the host's SSH host key is known.

if [ "$#" -ge 1 ]; then
  NAME="$1"
else
  NAME="$(gum input --header "Host name" --placeholder "web-1")"
  if [ -z "$NAME" ]; then
    gum log --level error "no host name given -- aborting"
    exit 1
  fi
fi

if [ ! -f hosts.nix ]; then
  gum log --level error "hosts.nix not found in CWD"
  exit 1
fi

if [ -z "${DISKO_PRESETS_DIR:-}" ] || [ ! -d "$DISKO_PRESETS_DIR" ]; then
  gum log --level error "DISKO_PRESETS_DIR is unset or missing -- run this from the devShell"
  exit 1
fi

# Bail if the host is already registered. Grep is imprecise but good enough
# for a well-formatted hosts.nix -- edge cases are on the operator.
if grep -qE "^[[:space:]]*${NAME}[[:space:]]*=[[:space:]]*\{" hosts.nix; then
  gum log --level error "host '${NAME}' already appears in hosts.nix"
  exit 1
fi

IP="$(gum input --header "IP address" --placeholder "1.2.3.4")"
if [ -z "$IP" ]; then
  gum log --level warn "no IP given -- aborting"
  exit 1
fi

# --- Disk layout preset ---
# Presets are plain .nix files under $DISKO_PRESETS_DIR. Filename (minus
# extension) is the label. `custom` is always available as an escape hatch:
# it skips disko.nix creation and reminds the operator to write it.
LAYOUT_OPTIONS=()
for f in "$DISKO_PRESETS_DIR"/*.nix; do
  [ -e "$f" ] || continue
  LAYOUT_OPTIONS+=("$(basename "$f" .nix)")
done
CUSTOM_LABEL="custom (write disko.nix by hand)"
LAYOUT_OPTIONS+=("$CUSTOM_LABEL")

LAYOUT="$(printf '%s\n' "${LAYOUT_OPTIONS[@]}" | gum choose --header "Disk layout")"
if [ -z "$LAYOUT" ]; then
  gum log --level error "no disk layout chosen -- aborting"
  exit 1
fi

# --- Scaffold hosts/<name>/ ---
mkdir -p "hosts/${NAME}"

# disko.nix: copy the chosen preset, or skip entirely for `custom`.
if [ "$LAYOUT" = "$CUSTOM_LABEL" ]; then
  gum log --level info "custom layout: hosts/${NAME}/disko.nix NOT created"
  gum log --level info "write it yourself before install-host ${NAME}"
  gum log --level info "  see docs/deploying/host-files.md and https://github.com/nix-community/disko/tree/master/example"
else
  if [ -f "hosts/${NAME}/disko.nix" ]; then
    gum log --level info "hosts/${NAME}/disko.nix already exists -- leaving it alone"
  else
    install -m 0644 "$DISKO_PRESETS_DIR/${LAYOUT}.nix" "hosts/${NAME}/disko.nix"
    gum log --level info "wrote hosts/${NAME}/disko.nix (${LAYOUT} preset)"
  fi
fi

# default.nix: entry point that stitches disko + hardware-config together.
# Operator adds per-host NixOS options here.
if [ -f "hosts/${NAME}/default.nix" ]; then
  gum log --level info "hosts/${NAME}/default.nix already exists -- leaving it alone"
else
  cat > "hosts/${NAME}/default.nix" <<'EOF'
# Entry point for this host. Imports the disk layout and the hardware
# config produced by install-host. Add per-host NixOS options below the
# imports.
{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
  ];
}
EOF
  gum log --level info "wrote hosts/${NAME}/default.nix"
fi

# hardware-configuration.nix: placeholder so `nix flake check` and other
# eval-time operations do not fail on the missing import. install-host
# overwrites this on first run via nixos-anywhere's --generate-hardware-config.
if [ -f "hosts/${NAME}/hardware-configuration.nix" ]; then
  gum log --level info "hosts/${NAME}/hardware-configuration.nix already exists -- leaving it alone"
else
  cat > "hosts/${NAME}/hardware-configuration.nix" <<'EOF'
# Placeholder -- install-host overwrites this via nixos-anywhere's
# --generate-hardware-config on first install. Any hand edits are lost.
{ ... }:
{
}
EOF
  gum log --level info "wrote hosts/${NAME}/hardware-configuration.nix (placeholder)"
fi

# --- Append entry to hosts.nix ---
# Insert immediately before the final `}`. Uses awk to defer printing so we
# can find the last closing brace reliably.
BLOCK="$(cat <<EOF

  ${NAME} = {
    ip      = "${IP}";
    modules = [ ./hosts/${NAME} ];
  };
EOF
)"

tmp="$(mktemp)"
awk -v block="$BLOCK" '
  { buf[NR] = $0 }
  END {
    close_line = 0
    for (i = 1; i <= NR; i++) if (buf[i] ~ /^\}[[:space:]]*$/) close_line = i
    if (close_line == 0) {
      print "!! add-host: could not find a closing } in hosts.nix" > "/dev/stderr"
      exit 1
    }
    for (i = 1; i < close_line; i++) print buf[i]
    print block
    for (i = close_line; i <= NR; i++) print buf[i]
  }
' hosts.nix > "$tmp"
mv "$tmp" hosts.nix

gum log --level info "hosts.nix updated -- next: install-host ${NAME}"
