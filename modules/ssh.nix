{ config, lib, ... }:
let
  cfg = config.nixops.ssh;
in
{
  options.nixops.ssh = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable openssh, key-only, root login with key permitted.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 22;
      description = "TCP port for sshd.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.openssh = {
      enable = true;
      ports = [ cfg.port ];
      settings = {
        PermitRootLogin = "prohibit-password";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
      };
      openFirewall = true;
    };
  };
}
