{
  lib,
  ...
}:
let
  inherit (builtins)
    attrNames
    attrValues
    readFile
    replaceStrings
    ;
  inherit (lib.modules) mkForce;

  loadFileWith =
    file: replacements:
    let
      content = readFile file;
    in
    replaceStrings (attrNames replacements) (attrValues replacements) content;
in
{

  _class = "nixosTest";

  imports = [ ./base-test.nix ];

  variant = "flake";

  nodes.machine =
    { config, pkgs, ... }:
    {
      _class = "nixos";
      config = {

        environment.etc."nixos/flake.nix" = {
          # must be a regular file so nix recognizes /etc/nixos as flake
          mode = "0644"; # -> makes file a regular file (instead of "symlink")
          text = loadFileWith ./flake-template.nix {
            "@hostName@" = config.networking.hostName;
            "@system@" = pkgs.stdenv.hostPlatform.system;
          };
        };

        nix.settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          flake-registry = ""; # avoid online registry
        };

        # otherwise the VM evaluates to a "different" updatedConfig
        # (default otherwise supplied lib.nixosConfig from <nixpkgs>/flake.nix)
        nixpkgs.flake.source = mkForce null;

        system.autoUpgrade = {
          flake = "/etc/nixos";
          flags = [
            "--override-input"
            "nixpkgs"
            "${pkgs.path}"
          ];
        };

      };
    };

}
