# update-secrets [<name>]
#
# Populate sops secrets for one host (or every host in the inventory).
# Reads the expected keys from
#   .#nixosConfigurations.<name>.config.sops.secrets
# and prompts (via gum) for any that are not yet set in secrets/<name>.yaml.
# Existing values are left untouched.

for f in flake.nix .sops.yaml; do
  if [ ! -f "$f" ]; then
    gum log --level error "$f not found in CWD"
    exit 1
  fi
done

NIX=(nix --extra-experimental-features "nix-command flakes")

# Convert "a/b/c" -> ["a"]["b"]["c"] for sops --set / --extract.
sops_path() {
  local key="$1"
  printf '["%s"]' "${key//\//\"][\"}"
}

ensure_encrypted_file() {
  local file="$1"
  [ -f "$file" ] && return 0
  mkdir -p "$(dirname "$file")"
  local tmp
  tmp="$(mktemp)"
  echo "{}" > "$tmp"
  # --filename-override tells sops which .sops.yaml rule to match; it is not
  # actually read. Silence the shellcheck read-and-write-same-file warning.
  # shellcheck disable=SC2094
  sops --encrypt --input-type=json --filename-override "$file" "$tmp" > "$file"
  rm -f "$tmp"
}

process_host() {
  local host="$1"
  local secrets_file="secrets/${host}.yaml"

  gum style --border rounded --padding "0 1" "$host"

  local secrets_out
  secrets_out=$("${NIX[@]}" eval --raw \
    --apply "attrs: builtins.concatStringsSep \"\\n\" (builtins.attrNames attrs)" \
    ".#nixosConfigurations.${host}.config.sops.secrets" 2>/dev/null || true)

  local -a secrets=()
  if [ -n "$secrets_out" ]; then
    mapfile -t secrets <<< "$secrets_out"
  fi

  if [ "${#secrets[@]}" -eq 0 ]; then
    gum log --level info "no sops secrets declared -- skipping"
    return 0
  fi

  ensure_encrypted_file "$secrets_file"

  local -a missing=()
  local key path
  for key in "${secrets[@]}"; do
    path="$(sops_path "$key")"
    if sops --decrypt --extract "$path" "$secrets_file" >/dev/null 2>&1; then
      gum log --level info "already set: $key"
    else
      missing+=("$key")
    fi
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    gum log --level info "all secrets present"
    return 0
  fi

  local value escaped
  for key in "${missing[@]}"; do
    path="$(sops_path "$key")"
    echo
    gum style --foreground 212 "${host} :: ${key}"
    value="$(gum input --placeholder "value for ${key}" --width 80 || true)"
    if [ -z "$value" ]; then
      gum log --level warn "empty -- skipping $key"
      continue
    fi
    escaped="$(printf "%s" "$value" | jq -Rs .)"
    sops --set "$path $escaped" "$secrets_file"
    gum log --level info "written"
  done
}

if [ "$#" -ge 1 ]; then
  process_host "$1"
else
  hosts_out="$("${NIX[@]}" eval --raw \
    --apply "attrs: builtins.concatStringsSep \"\\n\" (builtins.attrNames attrs)" \
    ".#nixosConfigurations")"
  mapfile -t hosts <<< "$hosts_out"

  if [ "${#hosts[@]}" -eq 0 ]; then
    gum log --level error "no hosts declared in this flake"
    exit 1
  fi

  for h in "${hosts[@]}"; do
    process_host "$h"
  done
fi
