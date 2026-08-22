{
  config,
  lib,
  ...
}:
let
  inherit (lib) types;
  inherit (lib.options) mkOption;
in
{

  _class = "nixosTest";

  options.variant = mkOption {
    type = types.str;
    description = "Name of the test variant";
  };

  config = {

    name = "auto-upgrade-${config.variant}";

    meta.maintainers = with lib.maintainers; [
      Zocker1999NET
    ];

    nodes.machine = ./base-config.nix;

    testScript = ''
      def assertIndicator(expected):
        result = machine.succeed("cat /etc/test-indicator").strip()
        assert result == expected, f"Expected {expected!r}, got {result!r}"

      machine.start()
      machine.wait_for_unit("multi-user.target")

      with subtest("initial indicator is BEFORE"):
        assertIndicator("BEFORE")

      with subtest("auto-upgrade switches the system"):
        # one-shot service, so will wait for finish & return appropriate exit code
        machine.succeed("systemctl start nixos-upgrade.service")

      with subtest("indicator after upgrade is AFTER"):
        assertIndicator("AFTER")
    '';

  };

}
