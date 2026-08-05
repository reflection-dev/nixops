{ config, lib, ... }:
let
  cfg = config.nixops.firewall;
in
{
  options.nixops.firewall = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable NixOS firewall in allowlist mode. SSH port is opened by the ssh module.";
    };
    allowedTCPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "Extra TCP ports to open (in addition to SSH).";
    };
    allowedUDPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "Extra UDP ports to open.";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall = {
      enable = true;
      allowedTCPPorts = cfg.allowedTCPPorts;
      allowedUDPPorts = cfg.allowedUDPPorts;
    };
  };
}
