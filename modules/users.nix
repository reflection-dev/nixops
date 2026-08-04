{ sshKeys, ... }: {
  # Root's authorized_keys is the single shared `sshKeys` list from the
  # instance flake — same set on every host, one place to rotate. Non-root
  # users are the fleet's own concern.
  users.users.root.openssh.authorizedKeys.keys = sshKeys;
}
