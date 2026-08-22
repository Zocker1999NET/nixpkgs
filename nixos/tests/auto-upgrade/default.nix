{ runTest }:
{
  flake = runTest ./flake-test.nix;
  storePathProvider = runTest ./storePathProvider-test.nix;
}
