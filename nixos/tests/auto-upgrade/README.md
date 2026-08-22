# auto-upgrade Test Design

Testing implementation of `system.autoUpgrade`.


## test variants

following configurations are tested:
- using `system.autoUpgrade.flake`
- using `system.autoUpgrade.storePathProvider`


## what is tested

- that upgrade service is available
- upgrade service determines correct next config
- upgrade service switches to expected config

- for `storePathProvider`: upgrade service can access at least localhost


### out of scope

- timed triggering of upgrade service
    (we trust systemd so far)
- activation scripts to update boot loader & its entries
- nix fetching an up to date flake from remote
- nix to build / substitute config toplevel
- nix `--update-input` to update flake.lock file
- nixos-rebuild to reexec into a newer self (see `--no-reexec`)


## Implementation

The VM config contains an test

Overall test plan, independent of test variant:
1. boot VM with `test.isUpdated = false;`
2. verify test-indicator file is "BEFORE"
3. run `nixos-upgrade.service`,
   -> switches to `test.isUpdated = true;`
4. verify test-indicator file is "AFTER"

The specific test variant configs need to:
- import `base-config.nix`
- configure `system.autoUpgrade` to use expected config source
- provide a target configuration for nixos-upgrade to evaluate & switch to
  - supplies & links to THIS nixpkgs
  - then passes `pkgs.nixosTests.auto-upgrade.nodes.machine.test.updatedConfig` as config
- work around specific quirks due to the test environment
  (e.g. no internet & no build dependencies)

We need exactly THIS nixpkgs & reflect on the test for `updatedConfig` s.t.:
- we can provide expected config as extra dependency to the closure
- nix inside VM evaluates to exactly the this expected config
- therefore no build dependencies are further required
