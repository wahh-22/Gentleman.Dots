{ config, pkgs, lib, ... }:

{
  # Copy a single repository-owned resource, never a managed Gentle Shell package.
  # The installer merges quietStartup and both banner-art flags under cooperative locks.
  # An absent isolated home is deliberately left for the launcher to bootstrap;
  # run gentle-shell --isolated once, then switch again to deploy into that home.
  home.activation.installPiKali = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/env \
      HOME=${lib.escapeShellArg config.home.homeDirectory} \
      ${pkgs.nodejs}/bin/node ${./pi/install-kali-widget.mjs} \
      ${./pi/extensions/kali-widget.ts}
  '';
}
