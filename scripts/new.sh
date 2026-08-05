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
  if [ -d "$NAME" ] && [ -z "$(ls -A "$NAME" 2>/dev/null)" ]; then
    : # empty directory -- populate in place
  else
    gum log --level error "'$NAME' already exists and is not an empty directory"
    exit 1
  fi
fi

if [ -z "${TEMPLATE_DIR:-}" ] || [ ! -d "$TEMPLATE_DIR" ]; then
  gum log --level error "TEMPLATE_DIR is not set or does not exist -- run this via 'nix run'"
  exit 1
fi

gum style --border rounded --padding "0 1" --foreground 212 "new fleet: $NAME"

# Small helper: after every answered step, print a one-line breadcrumb in
# muted grey so the operator (and screencast viewers) keep the running
# context above the next prompt.
crumb() { gum style --foreground 244 "  > $1"; }

DESCRIPTION="$(gum input --header "Description" --value "$NAME" --width 80)"
if [ -z "$DESCRIPTION" ]; then DESCRIPTION="$NAME"; fi
crumb "description: $DESCRIPTION"

# --- SSH keys ---
mapfile -t PUBKEYS < <(find "$HOME/.ssh" -maxdepth 1 -name "*.pub" -type f 2>/dev/null | sort)

CHOSEN_KEYS=()

if [ "${#PUBKEYS[@]}" -eq 0 ]; then
  if gum confirm "No SSH key in ~/.ssh. Generate an ed25519 pair?"; then
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "${USER:-nixops}@$(hostname)" >/dev/null
    key="$(cat "$HOME/.ssh/id_ed25519.pub")"
    CHOSEN_KEYS+=("$key")
    crumb "ssh key: generated ~/.ssh/id_ed25519"
  else
    line="$(gum input --header "SSH pubkey" --placeholder "ssh-ed25519 AAAA..." --width 100)"
    if [ -z "$line" ]; then
      gum log --level error "no SSH key provided -- aborting"
      exit 1
    fi
    CHOSEN_KEYS+=("$line")
    crumb "ssh key: (pasted)"
  fi
else
  # Single-select from ~/.ssh/*.pub via gum choose. gum choose takes over
  # the alternate screen for the duration of the picker; that is fine
  # because it is one screen for one question. The choice + breadcrumb
  # remains in scrollback afterwards. The instance flake.nix keeps the
  # sshKeys list schema -- add more entries by editing it directly.
  labels=()
  for f in "${PUBKEYS[@]}"; do
    labels+=("$(basename "$f")")
  done

  chosen_base="$(printf "%s\n" "${labels[@]}" | \
    gum choose --header "SSH key (one; add more later by editing flake.nix)")"

  if [ -z "$chosen_base" ]; then
    gum log --level error "no SSH key selected -- aborting"
    exit 1
  fi

  key="$(cat "$HOME/.ssh/$chosen_base")"
  if [ -z "$key" ]; then
    gum log --level error "$chosen_base is empty -- aborting"
    exit 1
  fi
  CHOSEN_KEYS+=("$key")
  crumb "ssh key: $chosen_base"
fi

# --- Age key ---
# Auto-use an existing key without prompting. Public key is derived from
# the private-key file via `age-keygen -y` -- never read the private-key
# file directly. Never write over an existing keys.txt.
AGE_FILE="$HOME/.config/sops/age/keys.txt"
AGE_PUB=""

if [ -f "$AGE_FILE" ]; then
  AGE_PUB="$(age-keygen -y "$AGE_FILE" 2>/dev/null | tail -1 || true)"
  if [ -z "$AGE_PUB" ]; then
    gum log --level error "cannot derive age public key from $AGE_FILE (age-keygen -y failed)"
    exit 1
  fi
else
  if gum confirm "No age key at $AGE_FILE. Generate one?"; then
    mkdir -p "$(dirname "$AGE_FILE")"
    age-keygen -o "$AGE_FILE" 2>/dev/null
    AGE_PUB="$(age-keygen -y "$AGE_FILE" | tail -1)"
  else
    AGE_PUB="$(gum input --header "age public key" --placeholder "age1..." --width 100)"
    if [ -z "$AGE_PUB" ]; then
      gum log --level error "no age recipient provided -- aborting"
      exit 1
    fi
  fi
fi
crumb "age recipient: ${AGE_PUB:0:20}..."

ADMIN_NAME="admin_${USER:-nixops}"
crumb "admin: $ADMIN_NAME"

# --- Scaffold ---
# cp -rT: if $NAME does not exist, it is created and populated; if it
# exists (and passed the empty-dir check above), contents are copied in.
mkdir -p "$NAME"
cp -rT "$TEMPLATE_DIR" "$NAME"
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
# The scaffold is a flake; nix flake commands want a tracked file to
# consider it "clean". Git init is unconditional -- no reason to leave
# the freshly-created repo in a state that trips flake tooling.
(cd "$NAME" && git init -q && git add -A && git commit -q -m "chore: scaffold fleet via nixops")
crumb "git: initialised"

gum style --border rounded --padding "0 1" --foreground 82 "created ./${NAME}/"
cat <<EOF

Next:
  cd ${NAME}
  nix develop
  add-host <name>
  install-host <name>
EOF
