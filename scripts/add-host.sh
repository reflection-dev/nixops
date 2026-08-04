# add-host [<name>]
#
# Interactive: prompts for the target IP (via gum), scaffolds
# hosts/<name>/hardware-configuration.nix, and appends an entry to
# hosts.nix keyed on <name>.
#
# If <name> is not given as an argument, prompts for it.
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

# hosts/<name>/hardware-configuration.nix -- stub, operator fills after
# nixos-anywhere or by running nixos-generate-config on the target.
mkdir -p "hosts/${NAME}"
if [ -f "hosts/${NAME}/hardware-configuration.nix" ]; then
  gum log --level info "hosts/${NAME}/hardware-configuration.nix already exists -- leaving it alone"
else
  cat > "hosts/${NAME}/hardware-configuration.nix" <<'EOF'
# Auto-generated stub -- replace with the file produced by:
#   nixos-generate-config --root /mnt --dir .
# on the target (nixos-anywhere runs this for you and prints the result;
# copy it here before the next deploy).
{ ... }: {
}
EOF
  gum log --level info "created hosts/${NAME}/hardware-configuration.nix (stub)"
fi

# Append the entry into hosts.nix, immediately before the final `}`. Uses
# awk to defer printing so we can find the last closing brace reliably.
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
