# set-secret <host> <key> <file>
#
# Non-interactive counterpart to `update-secrets`: reads <file> (or stdin
# when <file> is `-`) and writes its contents as the value of sops secret
# <key> for <host>. Existing value is overwritten.
#
# Useful in scripts and automation where the value comes from another
# command (openssl rand, age-keygen, kubectl get secret, ...).
#
# The file is read verbatim -- trailing newlines and all. If your value
# should not carry a trailing newline, trim it upstream (`printf %s` or
# `tr -d '\n'`) before piping in.

if [ "$#" -ne 3 ]; then
  gum log --level error "usage: set-secret <host> <key> <file|-|/dev/stdin>"
  exit 1
fi

HOST="$1"
KEY="$2"
FILE="$3"

for f in flake.nix .sops.yaml; do
  if [ ! -f "$f" ]; then
    gum log --level error "$f not found in CWD"
    exit 1
  fi
done

NIX=(nix --extra-experimental-features "nix-command flakes")

# Best-effort: warn (do not fail) if <key> is not declared in the host's
# sops.secrets. Catches typos without breaking bootstrap-time scripts
# that set values before the host is fully evaluatable.
declared_keys="$("${NIX[@]}" eval --raw \
  --apply "attrs: builtins.concatStringsSep \"\\n\" (builtins.attrNames attrs)" \
  ".#nixosConfigurations.${HOST}.config.sops.secrets" 2>/dev/null || true)"
if [ -n "$declared_keys" ]; then
  if ! printf '%s\n' "$declared_keys" | grep -Fxq "$KEY"; then
    gum log --level warn "key '$KEY' is not declared in sops.secrets of $HOST -- writing anyway"
  fi
fi

# Read value: stdin when FILE is `-`, otherwise the file's raw contents.
if [ "$FILE" = "-" ]; then
  value="$(cat)"
else
  if [ ! -r "$FILE" ]; then
    gum log --level error "$FILE not found or not readable"
    exit 1
  fi
  value="$(cat -- "$FILE")"
fi

SECRETS_FILE="secrets/${HOST}.yaml"

# Ensure the encrypted file exists (create empty {} + encrypt to the
# recipients .sops.yaml chose for this path). Copied verbatim from
# update-secrets.sh -- keep in sync if either changes.
if [ ! -f "$SECRETS_FILE" ]; then
  mkdir -p "$(dirname "$SECRETS_FILE")"
  tmp="$(mktemp)"
  echo "{}" > "$tmp"
  # shellcheck disable=SC2094
  sops --encrypt --input-type=json --filename-override "$SECRETS_FILE" "$tmp" > "$SECRETS_FILE"
  rm -f "$tmp"
fi

# Convert "a/b/c" -> ["a"]["b"]["c"] for `sops --set`. Copied verbatim
# from update-secrets.sh.
sops_path() {
  local key="$1"
  printf '["%s"]' "${key//\//\"][\"}"
}
path="$(sops_path "$KEY")"

# jq -Rs serialises arbitrary bytes as a JSON string (handles newlines,
# quotes, unicode). sops --set takes that JSON literal for the value.
escaped="$(printf "%s" "$value" | jq -Rs .)"
sops --set "$path $escaped" "$SECRETS_FILE"

gum log --level info "wrote $HOST :: $KEY ($(printf "%s" "$value" | wc -c) bytes)"
