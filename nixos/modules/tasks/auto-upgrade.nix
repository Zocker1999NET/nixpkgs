{
  config,
  lib,
  pkgs,
  ...
}:
let
  myPath = [
    "system"
    "autoUpgrade"
  ];
  cfg = config.system.autoUpgrade;
  sourceOptions = [
    "channel"
    "flake"
    "storePathProvider"
  ];
  sourceOptionsSet = lib.filter (x: cfg.${x} != null) sourceOptions;

  # helpers
  wrapString = wrapper: value: if lib.isString value then wrapper value else value;
in
{

  options = {

    system.autoUpgrade = {

      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to periodically upgrade NixOS to the latest
          version. If enabled, a systemd timer will run
          `nixos-rebuild switch --upgrade` once a
          day.
        '';
      };

      operation = lib.mkOption {
        type = lib.types.enum [
          "switch"
          "boot"
        ];
        default = "switch";
        example = "boot";
        description = ''
          Whether to run
          `nixos-rebuild switch --upgrade` or run
          `nixos-rebuild boot --upgrade`
        '';
      };

      flake = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "github:kloenk/nix";
        description = ''
          The Flake URI of the NixOS configuration to build.
          Disables the option {option}`system.autoUpgrade.channel`.
        '';
      };

      channel = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "https://channels.nixos.org/nixos-14.12-small";
        description = ''
          The URI of the NixOS channel to use for automatic
          upgrades. By default, this is the channel set using
          {command}`nix-channel` (run `nix-channel --list`
          to see the current value).
        '';
      };

      storePathProvider = lib.mkOption {
        # str chosen as not mergeable by design, as script must return exactly one store path -> combined definition is not feasible
        type = with lib.types; nullOr (either str package);
        default = null;
        apply = wrapString (pkgs.writeShellScriptBin "nixos-auto-upgrade-store-path");
        description = ''
          An executable that returns a NixOS system store path (of the toplevel closure) on stdout.

          The upgrade service will run this executable (via {var}`lib.meta.getExe`),
          then realize the returned store path via substitution,
          and pass it to {command}`nixos-rebuild --store-path`.

          This is useful when the NixOS configuration is evaluated and built on a remote build server,
          so that clients may also skip the evaluation of their own configuration.

          If a string is given, it is wrapped by {var}`pkgs.writeShellScriptBin`.
        '';
        example = lib.literalExpression "\${lib.getExe pkgs.curl} -s https://my-build-server.example.org/nixos-system-path";
      };

      upgrade = lib.mkOption {
        type = lib.types.bool;
        default = lib.length sourceOptionsSet == 0;
        defaultText = lib.pipe sourceOptions [
          (map (x: "config.${lib.showAttrPath myPath}.${x} == null"))
          (builtins.concatStringsSep " && ")
          lib.literalExpression
        ];
        description = ''
          Whether to add the `--upgrade` flag to {command}`nixos-rebuild`,
          which will update the root user's 'nixos' channel before building the new system generation.
          See {command}`nixos-rebuild --help` for more information about the `--upgrade` flag.

          In most cases, this only has a real effect when using channels
          with {option}`system.autoUpgrade.channel` set to null.

          Otherwise, {command}`nixos-rebuild` will always use the newest available system configuration
          as determined by the given channel, or flake (lock).
        '';
      };

      flags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "-I"
          "stuff=/home/alice/nixos-stuff"
          "--option"
          "extra-binary-caches"
          "http://my-cache.example.org/"
        ];
        description = ''
          Any additional flags passed to {command}`nixos-rebuild`.

          If you are using flakes and use a local repo you can add
          {command}`[ "--update-input" "nixpkgs" "--commit-lock-file" ]`
          to update nixpkgs.
        '';
      };

      dates = lib.mkOption {
        type = lib.types.str;
        default = "04:40";
        example = "daily";
        description = ''
          How often or when upgrade occurs. For most desktop and server systems
          a sufficient upgrade frequency is once a day.

          The format is described in
          {manpage}`systemd.time(7)`.
        '';
      };

      allowReboot = lib.mkOption {
        default = false;
        type = lib.types.bool;
        description = ''
          Reboot the system into the new generation instead of a switch
          if the new generation uses a different kernel, kernel modules
          or initrd than the booted system.
          See {option}`rebootWindow` for configuring the times at which a reboot is allowed.
        '';
      };

      randomizedDelaySec = lib.mkOption {
        default = "0";
        type = lib.types.str;
        example = "45min";
        description = ''
          Add a randomized delay before each automatic upgrade.
          The delay will be chosen between zero and this value.
          This value must be a time span in the format specified by
          {manpage}`systemd.time(7)`
        '';
      };

      fixedRandomDelay = lib.mkOption {
        default = false;
        type = lib.types.bool;
        example = true;
        description = ''
          Make the randomized delay consistent between runs.
          This reduces the jitter between automatic upgrades.
          See {option}`randomizedDelaySec` for configuring the randomized delay.
        '';
      };

      rebootWindow = lib.mkOption {
        description = ''
          Define a lower and upper time value (in HH:MM format) which
          constitute a time window during which reboots are allowed after an upgrade.
          This option only has an effect when {option}`allowReboot` is enabled.
          The default value of `null` means that reboots are allowed at any time.
        '';
        default = null;
        example = {
          lower = "01:00";
          upper = "05:00";
        };
        type =
          with lib.types;
          nullOr (submodule {
            options = {
              lower = lib.mkOption {
                description = "Lower limit of the reboot window";
                type = lib.types.strMatching "[[:digit:]]{2}:[[:digit:]]{2}";
                example = "01:00";
              };

              upper = lib.mkOption {
                description = "Upper limit of the reboot window";
                type = lib.types.strMatching "[[:digit:]]{2}:[[:digit:]]{2}";
                example = "05:00";
              };
            };
          });
      };

      persistent = lib.mkOption {
        default = true;
        type = lib.types.bool;
        example = false;
        description = ''
          Takes a boolean argument. If true, the time when the service
          unit was last triggered is stored on disk. When the timer is
          activated, the service unit is triggered immediately if it
          would have been triggered at least once during the time when
          the timer was inactive. Such triggering is nonetheless
          subject to the delay imposed by RandomizedDelaySec=. This is
          useful to catch up on missed runs of the service when the
          system was powered down.
        '';
      };

      runGarbageCollection = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to automatically run `nix-gc.service` after a successful
          system upgrade.
        '';
      };

    };

  };

  config = lib.mkIf cfg.enable {

    assertions = [
      {
        assertion = lib.length sourceOptionsSet <= 1;
        message = lib.pipe sourceOptionsSet [
          (map (x: lib.showAttrPath (myPath ++ [ x ])))
          (builtins.concatStringsSep ", ")
          (x: "Only one source option can be set at a time: ${x}")
        ];
      }
      {
        assertion = (cfg.runGarbageCollection -> config.nix.enable);
        message = ''
          The option 'system.autoUpgrade.runGarbageCollection = true' requires 'nix.enable = true'.
        '';
      }
      {
        assertion = (cfg.upgrade -> config.nix.channel.enable);
        message = "The option 'system.autoUpgrade.upgrade = true' requires 'nix.channel.enable = true' for updating the default 'nixos' channel.";
      }
    ];

    system.autoUpgrade = {
      flags = (
        if cfg.flake != null then
          [
            "--refresh"
            "--flake ${cfg.flake}"
          ]
        else if cfg.storePathProvider != null then
          [
            # path cached in var to avoid multiple calls of provider, see defining code in script
            ''--store-path "$store_path"''
          ]
        else
          [ "--no-build-output" ]
          ++ lib.optionals (cfg.channel != null) [
            "-I"
            "nixpkgs=${cfg.channel}/nixexprs.tar.xz"
          ]
      );
    };

    systemd.services.nixos-upgrade = {
      description = "NixOS Upgrade";

      restartIfChanged = false;
      unitConfig.X-StopOnRemoval = false;
      unitConfig.OnSuccess = lib.optional (
        cfg.runGarbageCollection && config.nix.enable
      ) "nix-gc.service";

      serviceConfig.Type = "oneshot";

      environment =
        config.nix.envVars
        // {
          inherit (config.environment.sessionVariables) NIX_PATH;
          HOME = "/root";
        }
        // config.networking.proxy.envVars;

      path = with pkgs; [
        coreutils
        gnutar
        xz.bin
        gzip
        gitMinimal
        config.nix.package.out
        config.programs.ssh.package
      ];

      script =
        let
          nix-store = "${config.nix.package}/bin/nix-store";
          nixos-rebuild = "${config.system.build.nixos-rebuild}/bin/nixos-rebuild";
          date = "${pkgs.coreutils}/bin/date";
          readlink = "${pkgs.coreutils}/bin/readlink";
          shutdown = "${config.systemd.package}/bin/shutdown";
          upgradeFlag = lib.optional cfg.upgrade "--upgrade";
        in
        ''
          ${lib.optionalString (cfg.storePathProvider != null) ''
            # cache in var to avoid multiple calls of provider
            store_path="$(${lib.getExe cfg.storePathProvider})"
            ${nix-store} --realize "$store_path"
          ''}

          ${
            if cfg.allowReboot then
              ''
                ${nixos-rebuild} boot ${toString (cfg.flags ++ upgradeFlag)}
                booted="$(${readlink} /run/booted-system/{initrd,kernel,kernel-modules})"
                built="$(${readlink} /nix/var/nix/profiles/system/{initrd,kernel,kernel-modules})"

                ${lib.optionalString (cfg.rebootWindow != null) ''
                  current_time="$(${date} +%H:%M)"

                  lower="${cfg.rebootWindow.lower}"
                  upper="${cfg.rebootWindow.upper}"

                  if [[ "''${lower}" < "''${upper}" ]]; then
                    if [[ "''${current_time}" > "''${lower}" ]] && \
                       [[ "''${current_time}" < "''${upper}" ]]; then
                      do_reboot="true"
                    else
                      do_reboot="false"
                    fi
                  else
                    # lower > upper, so we are crossing midnight (e.g. lower=23h, upper=6h)
                    # we want to reboot if cur > 23h or cur < 6h
                    if [[ "''${current_time}" < "''${upper}" ]] || \
                       [[ "''${current_time}" > "''${lower}" ]]; then
                      do_reboot="true"
                    else
                      do_reboot="false"
                    fi
                  fi
                ''}

                if [ "''${booted}" = "''${built}" ]; then
                  ${nixos-rebuild} ${cfg.operation} ${toString cfg.flags}
                ${lib.optionalString (cfg.rebootWindow != null) ''
                  elif [ "''${do_reboot}" != true ]; then
                    echo "Outside of configured reboot window, skipping."
                ''}
                else
                  ${shutdown} -r +1
                fi
              ''
            else
              ''
                ${nixos-rebuild} ${cfg.operation} ${toString (cfg.flags ++ upgradeFlag)}
              ''
          }
        '';

      startAt = cfg.dates;

      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };

    systemd.timers.nixos-upgrade = {
      timerConfig = {
        RandomizedDelaySec = cfg.randomizedDelaySec;
        FixedRandomDelay = cfg.fixedRandomDelay;
        Persistent = cfg.persistent;
      };
    };
  };

}
