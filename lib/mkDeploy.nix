# Turn a nixosConfigurations attrset into a deploy-rs `deploy.nodes` map.
# Reads target IP from `config.nixops.host.ip`; SSH login is root.
{ deploy-rs }:
nixosConfigurations:
builtins.mapAttrs (_name: nixosConfig: {
  hostname = nixosConfig.config.nixops.host.ip;
  sshUser = "root";
  profiles.system = {
    user = "root";
    path = deploy-rs.lib.${nixosConfig.pkgs.stdenv.hostPlatform.system}.activate.nixos nixosConfig;
  };
}) nixosConfigurations
