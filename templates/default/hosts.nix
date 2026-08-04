# Fleet inventory -- plain data. Each entry becomes a NixOS host named
# after its key.
#
# Add a host with:  nix develop -c add-host <name>
#
# Example:
#   web-1 = {
#     ip      = "1.2.3.4";
#     modules = [ ./hosts/web-1 ];
#   };

{ }
