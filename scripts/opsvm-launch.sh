# opsvm-launch: wrap the NixOS-generated run-opsvm-vm with a per-VM
# state dir on the host and a runtime hostname pushed via fw_cfg.
#
# Usage: nix run <flake>#opsvm -- [<name>] [-- QEMU-OPTS...]
#
# The first non-flag positional is the VM name; anything after it is
# forwarded to QEMU. Env OPSVM_NAME is the fallback when no positional
# is given (default: opsvm). Name doubles as the state-dir slug
# (<XDG_STATE_HOME>/nixops-opsvm/<name>/) and the guest hostname; must
# be a valid short hostname.
#
# Env:
#   OPSVM_NAME  fallback when no positional arg is given.
#   RAW_VM      set by the flake wrapper -- path to the built nixos-vm.

set -euo pipefail

if [ "${1-}" = "--help" ] || [ "${1-}" = "-h" ]; then
  cat >&2 <<'HELP'
Usage: nix run <flake>#opsvm -- [<name>] [QEMU-OPTS...]

  <name>       VM name (default: $OPSVM_NAME or "opsvm"). Slug for the
               host state dir and the guest hostname.

State dir: ${XDG_STATE_HOME:-$HOME/.local/state}/nixops-opsvm/<name>/
Contents:  opsvm.qcow2 (disk),
           ssh/       -> guest /home/ops/.ssh
           sops-age/  -> guest /home/ops/.config/sops/age
HELP
  exit 0
fi

# First positional is the name unless it looks like a flag (starts with `-`).
name=""
if [ $# -ge 1 ] && [ "${1#-}" = "$1" ]; then
  name="$1"
  shift
fi
name="${name:-${OPSVM_NAME:-opsvm}}"

if ! printf '%s' "$name" | grep -Eq '^[a-zA-Z][a-zA-Z0-9-]{0,62}$'; then
  echo "opsvm: OPSVM_NAME must start with a letter and contain only [a-zA-Z0-9-] (up to 63 chars); got '$name'" >&2
  exit 1
fi

if [ -z "${HOME:-}" ]; then
  echo "opsvm: HOME is unset; cannot resolve default state dir" >&2
  exit 1
fi

base="${XDG_STATE_HOME:-$HOME/.local/state}/nixops-opsvm"
state_dir="$base/$name"
ssh_dir="$state_dir/ssh"
age_dir="$state_dir/sops-age"
fleet_dir="$state_dir/fleet"
disk="$state_dir/opsvm.qcow2"

mkdir -p "$ssh_dir" "$age_dir" "$fleet_dir"
chmod 700 "$state_dir" "$ssh_dir" "$age_dir" "$fleet_dir"

cat >&2 <<EOF
opsvm '$name' state -> $state_dir
  qcow2 : $disk       (survives poweroff; rm to reset the VM)
  ssh   : $ssh_dir    -> guest /home/ops/.ssh
  age   : $age_dir    -> guest /home/ops/.config/sops/age
  fleet : $fleet_dir  -> guest /home/ops/$name  (autoscaffolded)

Different OPSVM_NAME values get separate state dirs and disks; the
guest hostname mirrors the name.
EOF

export NIX_DISK_IMAGE="$disk"
export QEMU_OPTS="${QEMU_OPTS:-} -fw_cfg name=opt/opsvm/hostname,string=$name -virtfs local,path=$ssh_dir,mount_tag=opsssh,security_model=mapped-xattr,writeout=immediate -virtfs local,path=$age_dir,mount_tag=opsage,security_model=mapped-xattr,writeout=immediate -virtfs local,path=$fleet_dir,mount_tag=opsfleet,security_model=mapped-xattr,writeout=immediate"

exec "$RAW_VM/bin/run-opsvm-vm" "$@"
