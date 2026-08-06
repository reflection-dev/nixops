# update-secrets [<host>]
#
# Re-encrypt `secrets/<host>.yaml` for the current recipient set in
# `.sops.yaml`. Use after rotating the admin key, after removing or
# adding a shared-file recipient, or any time `.sops.yaml` and an
# encrypted file's recipient wrappers drift out of sync.
#
# Values are unchanged; only the recipient wrappers change. Runs
# `sops updatekeys --yes` under the hood -- no prompts, no editing
# of values. Set values with `set-secret <host> <key> <file>` or by
# hand with `sops secrets/<host>.yaml`.
#
# Without arguments, resyncs every existing `secrets/*.yaml` file.

for f in flake.nix .sops.yaml; do
  if [ ! -f "$f" ]; then
    gum log --level error "$f not found in CWD"
    exit 1
  fi
done

resync_one() {
  local file="$1"
  if [ ! -f "$file" ]; then
    gum log --level warn "$file does not exist -- nothing to resync"
    return 0
  fi
  gum log --level info "sops updatekeys $file"
  sops updatekeys --yes "$file"
}

if [ "$#" -ge 1 ]; then
  resync_one "secrets/${1}.yaml"
else
  found=0
  for f in secrets/*.yaml; do
    [ -f "$f" ] || continue
    found=1
    resync_one "$f"
  done
  if [ "$found" -eq 0 ]; then
    gum log --level info "no secrets/*.yaml files -- nothing to resync"
  fi
fi
