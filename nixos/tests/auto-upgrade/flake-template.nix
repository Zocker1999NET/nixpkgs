# flake "providing" config inside the VM
{
  # substituted via flag --override-input
  inputs.nixpkgs.url = "nixpkgs";

  outputs =
    { nixpkgs, ... }:
    let
      # substituted at build time
      hostName = "@hostName@";
      system = "@system@";

      pkgs = nixpkgs.legacyPackages.${system};
      thisTest = pkgs.nixosTests.auto-upgrade.flake;
      ownNode = thisTest.nodes.${hostName};
    in
    {
      nixosConfigurations.machine = ownNode.test.updatedConfig;
    };
}
