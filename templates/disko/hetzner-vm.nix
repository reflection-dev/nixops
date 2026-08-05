# Hetzner Cloud VM (UEFI) -- single virtio disk at /dev/sda, GPT, ESP + ext4
# root, systemd-boot. Ships as the `Hetzner Cloud VM` preset selected during
# `add-host`.
#
# Also sets the boot loader here since it is tied to this partitioning
# choice: UEFI ESP at /boot + systemd-boot. Keeping both concerns in one file
# means picking the preset gives you a working boot on Hetzner Cloud without
# extra edits.
#
# If your target is not a UEFI Hetzner Cloud VM (BIOS-only, different disk
# name, multi-disk, ZFS, encryption, ...), pick `Custom` in `add-host` and
# write your own disko.nix + boot loader. See docs/deploying/host-files.md
# and https://github.com/nix-community/disko/tree/master/example.
{
  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  disko.devices.disk.main = {
    device = "/dev/sda";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
