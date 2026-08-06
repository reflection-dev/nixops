# Hetzner (BIOS/legacy) -- single disk at /dev/sda, GPT with a 1 MiB
# BIOS-boot partition, ext4 root, GRUB installed to the MBR. Ships as
# the `hetzner-bios` preset selected during `add-host`.
#
# Use this for Hetzner Dedicated (AX/EX) or any Cloud VM whose firmware
# is BIOS/CSM rather than UEFI. Symptom that you need this: the target
# reboots into "Booting from Hard Disk" and hangs after an install with
# the `hetzner-vm` (UEFI/systemd-boot) preset.
#
# Boot loader is set here since it is tied to the partitioning choice:
# BIOS GRUB on /dev/sda's MBR. Keeping both concerns in one file means
# picking the preset gives you a working boot without extra edits.
#
# If your target is not a single-disk BIOS host (multi-disk, ZFS,
# encryption, different disk name), pick `custom` in `add-host` and
# write your own disko.nix + boot loader. See docs/deploying/host-files.md
# and https://github.com/nix-community/disko/tree/master/example.
{
  boot.loader = {
    grub = {
      enable = true;
      # `devices` (list) is the modern form; `device` (scalar) gets
      # forwarded to `mirroredBoots.[0].devices` and can double up
      # with any other module that touches the same option.
      devices = [ "/dev/sda" ];
      efiSupport = false;
    };
    # systemd-boot is UEFI-only -- explicitly disable to make the
    # intent obvious and to catch accidental double-config.
    systemd-boot.enable = false;
  };

  disko.devices.disk.main = {
    device = "/dev/sda";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        # 1 MiB BIOS-boot partition: GRUB embeds its core.img here on
        # GPT systems (there is no MBR post-code gap on GPT). Type
        # ef02 marks it as bios_grub for `disko`.
        boot = {
          size = "1M";
          type = "EF02";
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
