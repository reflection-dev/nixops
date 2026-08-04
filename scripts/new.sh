# new [new] <fleet-name>
#
# Interactive scaffold for a fresh instance repo. Copies TEMPLATE_DIR
# into ./<fleet-name>, then rewrites the sentinel-marked spots with
# real values collected through gum prompts.
#
# TEMPLATE_DIR is set by the flake app wrapper to the nix-store path of
# templates/default. Run this via `nix run <nixops> -- new <name>`.

# `nix run <nixops> -- new <name>` passes "new" as the first arg because
# the default app does no subcommand routing. Skip it if present.
if [ "${1:-}" = "new" ]; then shift; fi

NAME="${1:-}"

if [ -z "$NAME" ]; then
  gum log --level error "usage: new <fleet-name>"
  exit 1
fi

if [ -e "$NAME" ]; then
  gum log --level error "'$NAME' already exists"
  exit 1
fi

if [ -z "${TEMPLATE_DIR:-}" ] || [ ! -d "$TEMPLATE_DIR" ]; then
  gum log --level error "TEMPLATE_DIR is not set or does not exist -- run this via 'nix run'"
  exit 1
fi

gum style --border rounded --padding "0 1" --foreground 212 "new fleet: $NAME"

DESCRIPTION="$(gum input --header "Description" --value "$NAME" --width 80)"
if [ -z "$DESCRIPTION" ]; then DESCRIPTION="$NAME"; fi

# --- SSH keys ---
mapfile -t PUBKEYS < <(find "$HOME/.ssh" -maxdepth 1 -name "*.pub" -type f 2>/dev/null | sort)

CHOSEN_KEYS=()
if [ "${#PUBKEYS[@]}" -eq 0 ]; then
  gum log --level info "no ~/.ssh/*.pub found -- enter one key at a time (empty line to finish)"
  while :; do
    line="$(gum input --header "SSH pubkey (empty to finish)" --width 100)"
    if [ -z "$line" ]; then break; fi
    CHOSEN_KEYS+=("$line")
  done
else
  labels=()
  for f in "${PUBKEYS[@]}"; do
    labels+=("$(basename "$f")  --  $(cut -c1-70 < "$f")...")
  done
  mapfile -t SELECTED < <(printf "%s\n" "${labels[@]}" | gum choose --no-limit --header "SSH keys (space to toggle, enter to confirm)")
  for sel in "${SELECTED[@]}"; do
    base="${sel%%  --  *}"
    key="$(cat "$HOME/.ssh/$base")"
    CHOSEN_KEYS+=("$key")
  done
fi

if [ "${#CHOSEN_KEYS[@]}" -eq 0 ]; then
  gum log --level warn "no ssh keys selected -- root will be unreachable until you edit flake.nix"
fi

# --- Age key ---
AGE_FILE="$HOME/.config/sops/age/keys.txt"
AGE_PUB=""
if [ -f "$AGE_FILE" ]; then
  AGE_PUB="$(grep -oE 'age1[a-z0-9]+' "$AGE_FILE" | tail -1 || true)"
  if [ -n "$AGE_PUB" ]; then
    if ! gum confirm "Use age key $AGE_PUB from $AGE_FILE?"; then
      AGE_PUB=""
    fi
  fi
fi

if [ -z "$AGE_PUB" ]; then
  if gum confirm "Generate a new age key at $AGE_FILE?"; then
    mkdir -p "$(dirname "$AGE_FILE")"
    age-keygen -o "$AGE_FILE"
    AGE_PUB="$(grep -oE 'age1[a-z0-9]+' "$AGE_FILE" | tail -1)"
  else
    AGE_PUB="$(gum input --header "age public key" --placeholder "age1...")"
  fi
fi

ADMIN_NAME="$(gum input --header "Admin recipient name" --value "admin_${USER}")"

# --- Scaffold ---
cp -r "$TEMPLATE_DIR" "$NAME"
chmod -R u+w "$NAME"
cd "$NAME"

# Description: single-line sed swap keyed on the sentinel.
sed -i "s|description = \"my-fleet\";.*NIXOPS_DESCRIPTION.*\$|description = \"${DESCRIPTION}\";|" flake.nix

# SSH keys: write the collected keys to a temp file, then awk-replace the
# START/END block with quoted string literals for each key.
keys_tmp="$(mktemp)"
for k in "${CHOSEN_KEYS[@]}"; do
  printf "%s\n" "$k" >> "$keys_tmp"
done

out="$(mktemp)"
awk -v keys_file="$keys_tmp" '
  BEGIN {
    inblock = 0
    nk = 0
    while ((getline line < keys_file) > 0) klines[++nk] = line
    close(keys_file)
  }
  /NIXOPS_SSH_KEYS_START/ {
    print
    for (i = 1; i <= nk; i++) print "      \"" klines[i] "\""
    inblock = 1
    next
  }
  /NIXOPS_SSH_KEYS_END/ { inblock = 0; print; next }
  !inblock { print }
' flake.nix > "$out"
mv "$out" flake.nix
rm -f "$keys_tmp"

# Admin recipient line in .sops.yaml.
sed -i "s|- &admin_you   age1REPLACE_WITH_YOUR_LAPTOP_AGE_PUBLIC_KEY.*NIXOPS_ADMIN_LINE.*\$|- \&${ADMIN_NAME}   ${AGE_PUB}|" .sops.yaml

cd ..

# --- Git ---
if gum confirm "Initialise git repo?"; then
  (cd "$NAME" && git init -q && git add -A && git commit -q -m "chore: scaffold fleet via nixops")
fi

# --- First host ---
if gum confirm "Add a host now?"; then
  (
    cd "$NAME"
    HOSTNAME_INPUT="$(gum input --header "Host name" --placeholder "web-1")"
    if [ -n "$HOSTNAME_INPUT" ]; then
      nix --extra-experimental-features "nix-command flakes" develop -c add-host "$HOSTNAME_INPUT" || true
    fi
  )
fi

gum style --border rounded --padding "0 1" --foreground 82 "created ./${NAME}/"
cat <<EOF

Next:
  cd ${NAME}
  nix develop
  install-host <name>
EOF
