{
  config,
  extendModules,
  lib,
  # local test helpers
  updatedConfigPath,
  whenOriginal,
  whenUpdatedElse,
  ...
}:
let
  inherit (lib.lists) singleton;
  inherit (lib.modules) mkForce mkIf;
  inherit (lib.options) mkEnableOption mkOption;

  cfg = config.test;
in
{

  _class = "nixos";

  options.test = {

    isUpdated = mkEnableOption "updated config";

    updatedConfig = mkOption {
      description = "The config auto-upgrade should switch to.";
      internal = true;
      # same config but with flag flipped
      default = extendModules {
        modules = singleton {
          test = {
            isUpdated = true;
            # terminate undetected infinite recursion (thx halting problem)
            # happens when using `updatedConfig` from updated config
            updatedConfig = abort "infinite recursion on updatedConfig";
          };
        };
      };
    };

  };

  config = {

    # helpers for local test logic
    _module.args = {
      updatedConfigPath = cfg.updatedConfig.config.system.build.toplevel;
      whenUpdated = v: mkIf cfg.isUpdated (mkForce v);
      whenOriginal = v: mkIf (!cfg.isUpdated) (mkForce v);
      whenUpdatedElse = updated: original: if cfg.isUpdated then updated else original;
    };

    # boot loader installations fail in tests because disk has no partitions (test driver uses directBoot)
    boot.loader.grub.enable = false; # was enabled by default

    environment.etc."test-indicator".text = whenUpdatedElse "AFTER" "BEFORE";

    nix.settings = {
      connect-timeout = 1; # fail fast on accidental network access
      hashed-mirrors = null; # avoid substitutions
      substituters = mkForce [ ]; # avoid substitutions
    };

    system = {

      autoUpgrade = {
        enable = true;
        dates = "1960-01-01 00:00:00"; # force manual execution only
        flags = [
          "--no-reexec" # out of scope (& fails on some test variants)
        ];
      };

      # serve target system closure -> no build dependencies required
      extraDependencies = whenOriginal [ updatedConfigPath ];

      switch.enable = true; # disabled by default in test driver

    };

    virtualisation = {

      cores = 2;
      memorySize = 2048;
      diskSize = 4096;

      # Nix copies nixpkgs from store into store, see:
      # https://github.com/NixOS/nix/issues/7075#issuecomment-5357445643
      writableStore = true;

      # avoid tmpfs so that low RAM is not used for built artifacts
      writableStoreUseTmpfs = false;

      # increase performance for accessing passed-through nixpkgs source
      # (generating nix store image is faster than accessing nixpkgs through 9p)
      useNixStoreImage = true;
    };

  };

}
