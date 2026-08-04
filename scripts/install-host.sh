# install-host <name> [--force]
#
# Bootstrap a host via nixos-anywhere. Reads ip from hosts.nix, generates
# an ed25519 SSH host key locally, derives its age recipient, injects it
# into .sops.yaml, prompts for missing sops secrets (via update-secrets),
# ships everything as --extra-files, then removes the local copy so the
# private key only lives on the target.
#
# --force: allow overwriting a target that already runs NixOS.

FORCE=0
NAME=""
for a in "$@"; do
  case "$a" in
    --force) FORCE=1 ;;
    --*)     gum log --level error "unknown flag: $a"; exit 1 ;;
    *)       NAME="$a" ;;
  esac
done

if [ -z "$NAME" ]; then
  gum log --level error "usage: install-host <name> [--force]"
  exit 1
fi

for f in flake.nix hosts.nix; do
  if [ ! -f "$f" ]; then
    gum log --level error "$f not found in CWD (run from your instance repo)"
    exit 1
  fi
done

NIX=(nix --extra-experimental-features "nix-command flakes")

IP="$("${NIX[@]}" eval --raw --impure --expr "(import ./hosts.nix).${NAME}.ip" 2>/dev/null || true)"
if [ -z "$IP" ]; then
  gum log --level error "host '${NAME}' not found in hosts.nix (or missing 'ip')"
  exit 1
fi

gum style --border rounded --padding "0 1" "install ${NAME} @ ${IP}"

# Refuse to wipe a target that is already NixOS unless --force.
if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
       "root@${IP}" "test -f /etc/NIXOS" 2>/dev/null; then
  if [ "$FORCE" -eq 0 ]; then
    gum log --level error "${IP} is already running NixOS. Re-run with --force to wipe and reinstall."
    exit 1
  fi
  gum log --level warn "${IP} is NixOS; --force set, proceeding with wipe + reinstall"
fi

SSH_KEY="secrets/${NAME}/ssh/ssh_host_ed25519_key"

# Does this host declare any sops secrets? Sops setup only kicks in then.
SECRETS_COUNT="$("${NIX[@]}" eval --raw \
                  --apply "attrs: toString (builtins.length (builtins.attrNames attrs))" \
                  ".#nixosConfigurations.${NAME}.config.sops.secrets" 2>/dev/null || echo 0)"
USE_SECRETS=0
if [ "$SECRETS_COUNT" -gt 0 ]; then USE_SECRETS=1; fi

if [ "$USE_SECRETS" -eq 1 ]; then
  if [ ! -f .sops.yaml ]; then
    gum log --level error ".sops.yaml is missing but ${NAME} declares sops secrets."
    echo
    # shellcheck disable=SC2016
    cat <<EOF
Generate an age key and a minimal .sops.yaml, then re-run:

  mkdir -p ~/.config/sops/age
  age-keygen -o ~/.config/sops/age/keys.txt
  pub=\$(grep -oE 'age1[a-z0-9]+' ~/.config/sops/age/keys.txt | tail -1)
  cat > .sops.yaml <<YAML
  keys:
    - &admin_${USER}  \$pub
  creation_rules: []
  YAML
EOF
    exit 1
  fi
  if ! grep -qE "^  - &admin_" .sops.yaml; then
    gum log --level error ".sops.yaml has no admin recipient (expected an anchor named '&admin_<something>')."
    exit 1
  fi

  if [ ! -f "$SSH_KEY" ]; then
    gum log --level info "generating SSH host key at $SSH_KEY"
    mkdir -p "$(dirname "$SSH_KEY")"
    ssh-keygen -t ed25519 -N "" -C "${NAME}" -f "$SSH_KEY" >/dev/null
  fi

  AGE_RECIPIENT="$(ssh-to-age -i "${SSH_KEY}.pub")"
  gum log --level info "age recipient: ${AGE_RECIPIENT}"

  if grep -qF "$AGE_RECIPIENT" .sops.yaml; then
    gum log --level info ".sops.yaml already has this recipient"
  elif grep -qE "^  - &${NAME}[[:space:]]" .sops.yaml; then
    gum log --level info "updating .sops.yaml anchor &${NAME}"
    sed -i -E "s|^(  - &${NAME}[[:space:]]+)age1[a-z0-9]+|\\1${AGE_RECIPIENT}|" .sops.yaml
    if [ -f "secrets/${NAME}.yaml" ]; then
      sops updatekeys --yes "secrets/${NAME}.yaml"
    fi
  else
    gum log --level info "adding anchor &${NAME} to .sops.yaml"
    # Append the host anchor and a matching creation_rule. Very light-touch
    # editing so it does not fight with a hand-tuned .sops.yaml.
    tmp="$(mktemp)"
    awk -v host="${NAME}" -v recip="${AGE_RECIPIENT}" '
      BEGIN { in_keys=0; last_anchor_idx=0; buf_n=0 }
      /^keys:/ { in_keys=1; buf_n++; buf[buf_n]=$0; next }
      in_keys && /^[a-z]/ {
        in_keys=0
        for (i=1; i<=last_anchor_idx; i++) print buf[i]
        printf "  - &%s    %s\n", host, recip
        for (i=last_anchor_idx+1; i<=buf_n; i++) print buf[i]
        print
        next
      }
      in_keys {
        buf_n++; buf[buf_n]=$0
        if (/^  - &/) last_anchor_idx=buf_n
        next
      }
      { print }
      END {
        if (in_keys) {
          for (i=1; i<=last_anchor_idx; i++) print buf[i]
          printf "  - &%s    %s\n", host, recip
          for (i=last_anchor_idx+1; i<=buf_n; i++) print buf[i]
        }
      }
    ' .sops.yaml > "$tmp"

    admins=$(grep -oE '^  - &admin_[[:alnum:]_]+' "$tmp" | awk '{print $NF}' | sed 's/^&//')
    age_list=""
    for a in $admins "${NAME}"; do age_list="${age_list}*${a}, "; done
    age_list="${age_list%, }"
    if [ -n "$(tail -c 1 "$tmp")" ]; then printf "\n" >> "$tmp"; fi
    {
      echo "  - path_regex: secrets/${NAME}\\.yaml\$"
      echo "    key_groups:"
      echo "      - age: [ ${age_list} ]"
    } >> "$tmp"
    mv "$tmp" .sops.yaml

    if [ -f "secrets/${NAME}.yaml" ]; then
      sops updatekeys --yes "secrets/${NAME}.yaml"
    fi
  fi

  gum log --level info "checking sops secrets for ${NAME}"
  update-secrets "$NAME"
fi

EXTRA="$(mktemp -d)"
trap 'rm -rf "$EXTRA"' EXIT

if [ "$USE_SECRETS" -eq 1 ]; then
  install -Dm 0400 "$SSH_KEY"       "$EXTRA/etc/ssh/ssh_host_ed25519_key"
  install -Dm 0444 "${SSH_KEY}.pub" "$EXTRA/etc/ssh/ssh_host_ed25519_key.pub"
fi

gum style --border rounded --padding "0 1" "invoking nixos-anywhere on root@${IP}"

nixos-anywhere \
  --flake ".#${NAME}" \
  --extra-files "$EXTRA" \
  "root@${IP}"

# nixos-anywhere succeeded (set -e). The private key now lives on the
# target; drop the local copy.
if [ "$USE_SECRETS" -eq 1 ]; then
  gum log --level info "install complete; removing local host key (it lives on ${NAME} now)"
  rm -rf "secrets/${NAME}"
fi
