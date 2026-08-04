{ ... }: {
  # Derive the host's age identity from its ed25519 SSH host key. Available
  # from the first boot after nixos-anywhere installs the key. Encrypt secrets
  # for this host by adding its derived age recipient to `.sops.yaml`; get the
  # recipient with `ssh-to-age -i /etc/ssh/ssh_host_ed25519_key.pub`.
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
}
