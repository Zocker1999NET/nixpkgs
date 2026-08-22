{
  lib,
  ...
}:
let
  inherit (lib.meta) getExe;
in
{

  _class = "nixosTest";

  imports = [ ./base-test.nix ];

  variant = "storePathProvider";

  nodes.machine =
    {
      pkgs,
      # local test helpers
      updatedConfigPath,
      whenOriginal,
      ...
    }:
    {
      _class = "nixos";
      config = {

        # simulate "remote" service providing current store path
        services.static-web-server = whenOriginal {
          enable = true;
          listen = "80";
          root = "${pkgs.writeTextDir "your-store-path" "${updatedConfigPath}"}";
        };

        # confirm network capabilities
        system.autoUpgrade.storePathProvider = "${getExe pkgs.curl} http://localhost:80/your-store-path";

      };
    };

}
