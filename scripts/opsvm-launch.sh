# opsvm-launch: wrap the NixOS-generated run-opsvm-vm with a per-VM
# state dir on the host and a runtime hostname pushed via fw_cfg.
#
# Env:
#   OPSVM_NAME  VM name (default: opsvm). Doubles as the state-dir slug
#               (<XDG_STATE_HOME>/nixops-opsvm/<name>/) and the guest
#               hostname. Must be a valid short hostname.
#   RAW_VM      set by the flake wrapper -- path to the built nixos-vm.

set -euo pipefail

name="${OPSVM_NAME:-opsvm}"

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
disk="$state_dir/opsvm.qcow2"

mkdir -p "$ssh_dir" "$age_dir"
chmod 700 "$state_dir" "$ssh_dir" "$age_dir"

cat >&2 <<EOF
opsvm '$name' state -> $state_dir
  qcow2 : $disk    (survives poweroff; rm to reset the VM)
  ssh   : $ssh_dir -> guest /home/ops/.ssh
  age   : $age_dir -> guest /home/ops/.config/sops/age

Different OPSVM_NAME values get separate state dirs and disks; the
guest hostname mirrors the name.
EOF

export NIX_DISK_IMAGE="$disk"
export QEMU_OPTS="${QEMU_OPTS:-} -fw_cfg name=opt/opsvm/hostname,string=$name -virtfs local,path=$ssh_dir,mount_tag=opsssh,security_model=mapped-xattr,writeout=immediate -virtfs local,path=$age_dir,mount_tag=opsage,security_model=mapped-xattr,writeout=immediate"

exec "$RAW_VM/bin/run-opsvm-vm" "$@"
