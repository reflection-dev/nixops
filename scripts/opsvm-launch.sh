# opsvm-launch: wrap the NixOS-generated run-opsvm-vm with a persistent
# host state dir. Keys and the qcow2 disk live outside the VM so kills
# and rebuilds do not lose them; the default path is a dedicated
# sandbox, not ~/.ssh, so real keys are never mixed in.
#
# Env:
#   OPSVM_STATE_DIR  override state dir (default: $XDG_STATE_HOME/nixops-opsvm
#                    or $HOME/.local/state/nixops-opsvm)
#   RAW_VM           set by the flake wrapper -- path to the built nixos-vm

set -euo pipefail

if [ -z "${HOME:-}" ]; then
  echo "opsvm: HOME is unset; cannot resolve default state dir" >&2
  exit 1
fi

if [ -n "${OPSVM_STATE_DIR:-}" ]; then
  state_dir="$OPSVM_STATE_DIR"
else
  base="${XDG_STATE_HOME:-$HOME/.local/state}"
  state_dir="$base/nixops-opsvm"
fi

ssh_dir="$state_dir/ssh"
age_dir="$state_dir/sops-age"
disk="$state_dir/opsvm.qcow2"

mkdir -p "$ssh_dir" "$age_dir"
chmod 700 "$state_dir" "$ssh_dir" "$age_dir"

cat >&2 <<EOF
opsvm state -> $state_dir
  qcow2 : $disk    (survives poweroff; rm to reset the VM)
  ssh   : $ssh_dir -> guest /home/ops/.ssh
  age   : $age_dir -> guest /home/ops/.config/sops/age

Override with OPSVM_STATE_DIR=<path>. Do NOT point it at your real
~/.ssh or ~/.config/sops/age -- the sandbox is the whole point.
EOF

export NIX_DISK_IMAGE="$disk"
export QEMU_OPTS="${QEMU_OPTS:-} -virtfs local,path=$ssh_dir,mount_tag=opsssh,security_model=mapped-xattr,writeout=immediate -virtfs local,path=$age_dir,mount_tag=opsage,security_model=mapped-xattr,writeout=immediate"

exec "$RAW_VM/bin/run-opsvm-vm" "$@"
