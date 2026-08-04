# deploy [<name>]
#
# Thin wrapper over deploy-rs. Without arguments, deploys every node in
# the current flake's deploy.nodes attrset. With a <name>, deploys only
# that host: forwards to `deploy .#<name>`.
#
# Any remaining args are passed through, so `deploy web-1 --skip-checks`
# and friends work as expected.

if [ ! -f flake.nix ]; then
  gum log --level error "flake.nix not found in CWD"
  exit 1
fi

if [ "$#" -eq 0 ]; then
  exec deploy .
fi

NAME="$1"
shift

case "$NAME" in
  -*|.*)
    # Not a hostname -- forward everything untouched (e.g. --help).
    exec deploy "$NAME" "$@"
    ;;
  *)
    exec deploy ".#${NAME}" "$@"
    ;;
esac
