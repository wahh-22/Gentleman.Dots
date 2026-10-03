{
  description = "Gentleman: Single config for all systems in one go";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";  # Home Manager repository
      inputs.nixpkgs.follows = "nixpkgs";  # Follow nixpkgs input
    };
    flake-utils.url = "github:numtide/flake-utils";  # Flake utilities
  };

  outputs = { nixpkgs, nixpkgs-unstable, home-manager, flake-utils, ... }:
    let
      # Support macOS systems only
      supportedSystems = [ "x86_64-darwin" "aarch64-darwin" ];
      
      # ─── User Configuration ───
      # Change this to your macOS username
      username = "alanbuscaglia";

      # Function to create home configuration for a specific system
      mkHomeConfiguration = system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
          nodeWithoutNpm = pkgs.runCommand "nodejs-without-npm-${pkgs.nodejs.version}" { } ''
            mkdir -p "$out/bin"
            ln -s ${pkgs.nodejs}/bin/node "$out/bin/node"
            ln -s ${pkgs.nodejs}/bin/corepack "$out/bin/corepack"
          '';
          
          unstablePkgs = import nixpkgs-unstable {
            inherit system;
            config.allowUnfree = true;
          };
        in
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          
          # Pass extraSpecialArgs to make unstablePkgs available in modules
          extraSpecialArgs = {
            inherit unstablePkgs;
          };
          
          modules = [
            ./nushell.nix  # Nushell configuration
            ./ghostty.nix  # Ghostty configuration
            ./alacritty.nix  # Alacritty configuration
            ./zed.nix  # Zed configuration
            ./television.nix  # Television configuration
            ./wezterm.nix  # WezTerm configuration
            ./kitty.nix  # Kitty configuration
            ./zellij.nix  # Zellij configuration
            ./tmux.nix  # Tmux configuration
            ./tmux-agents.nix  # Tmux agent-state notifier (working/blocked/idle)
            ./pi-kali.nix  # Repository-owned Pi widget and safe startup config merges
            ./fish.nix  # Fish shell configuration
            ./starship.nix  # Starship prompt configuration
            ./nvim.nix  # Neovim configuration
            ./zsh.nix  # Zsh configuration
            ./oil-scripts.nix  # Oil.nvim scripts configuration
            ./opencode.nix  # OpenCode AI assistant configuration
            ./claude.nix  # Claude Code CLI configuration
            ./engram.nix  # Engram memory layer for AI agents
            ./herdr.nix  # Herdr agent multiplexer configuration
            ./posting.nix  # Posting terminal HTTP client
            ./yabai.nix  # Yabai window manager configuration
            ./skhd.nix  # Skhd hotkey daemon configuration
            # Nehir (Niri-style WM) trial reverted — back to yabai/skhd/sketchybar.
            # nehir.nix and nehir/ config are kept in the repo for a future retry.
            # ./nehir.nix  # Nehir (Niri-style WM) configuration
            # ./simple-bar.nix  # simple-bar for Übersicht (disabled - using sketchybar)
            ./sketchybar.nix  # SketchyBar status bar
            ./raycast.nix  # Raycast scripts
            {
              # Personal data
              home.username = "wilmerhenao";  # Replace with your username
              home.homeDirectory = "/Users/wilmerhenao/";  # macOS home directory
              home.stateVersion = "24.11";  # State version

              # Base packages that should be available everywhere
              home.packages = with pkgs; [
                # ─── Terminals and utilities ───
                zellij
                tmux
                fish
                zsh
                nushell

                # ─── Window management (macOS) ───
                # yabai, skhd, and sketchybar are installed via Homebrew modules.

                # ─── Development tools ───
                carapace
                zoxide
                atuin
                jq
                bash
                starship
                fzf
                nodeWithoutNpm
                unstablePkgs.pnpm
                bun
                cargo
                go
                nil
                unstablePkgs.nixd
                unstablePkgs.neovim
                tree-sitter

                # ─── Compilers and system utilities ───
                gcc
                fd
                ripgrep
                coreutils
                unzip
                bat
                lazygit
                yazi
                television

                # ─── Nerd Fonts ───
                nerd-fonts.iosevka-term
              ];

              # This flake supports macOS only. Without XDG_CONFIG_HOME, Lazygit
              # reads ~/Library/Application Support/lazygit/config.yml. Home Manager
              # refuses to replace an existing unmanaged file (no force/backup option
              # here): move or merge that file manually before activation. If a shell
              # sets XDG_CONFIG_HOME, Lazygit instead reads $XDG_CONFIG_HOME/lazygit;
              # this static Home Manager target does not follow that override.
              home.file."Library/Application Support/lazygit/config.yml".source = ./config/lazygit/config.yml;

              # Enable programs explicitly (critical for binaries to appear)
              # All program enables are centralized here
              programs.neovim.enable = false;
              programs.fish.enable = true;
              programs.nushell.enable = true;
              programs.starship.enable = false;
              programs.zsh.enable = false;  # Managed via home.file in zsh.nix
              programs.git.enable = true;
              programs.gh.enable = true;  # GitHub CLI
              programs.home-manager.enable = true;
              # Note: tmux is configured via home.file in tmux.nix, not programs.tmux

              # NOTE: home.sessionVariables removed - it generates a recursive .zshenv bug
              # XDG_CONFIG_HOME is set in shell configs instead

              # Allow unfree packages
              nixpkgs.config.allowUnfree = true;
            }
          ];
        };
    in
    {
      checks = builtins.listToAttrs (map (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          name = system;
          value.ai-quota = pkgs.runCommand "ai-quota-test" {
            nativeBuildInputs = with pkgs; [
              bash
              coreutils
              gawk
              git
              gnugrep
              gnused
              jq
              python3
            ];
          } ''
            export HOME="$TMPDIR/home"
            export XDG_CACHE_HOME="$TMPDIR/cache"
            test_root="$TMPDIR/ai-quota-test-source"
            mkdir -p "$HOME" "$XDG_CACHE_HOME" \
              "$test_root/claude" \
              "$test_root/sketchybar/plugins" \
              "$test_root/sketchybar/tests"
            cp ${./claude/statusline.sh} "$test_root/claude/statusline.sh"
            cp ${./sketchybar/plugins/ai_quota.sh} "$test_root/sketchybar/plugins/ai_quota.sh"
            cp ${./sketchybar/sketchybarrc} "$test_root/sketchybar/sketchybarrc"
            cp ${./sketchybar/tests/ai_quota_test.sh} "$test_root/sketchybar/tests/ai_quota_test.sh"
            bash "$test_root/sketchybar/tests/ai_quota_test.sh"
            touch "$out"
          '';
        }) supportedSystems);

      # Home Manager configurations for each system
      homeConfigurations = {
        # macOS system configurations
        "gentleman-macos-intel" = mkHomeConfiguration "x86_64-darwin";
        "gentleman-macos-arm" = mkHomeConfiguration "aarch64-darwin";
        
        # Default to Apple Silicon
        "gentleman" = mkHomeConfiguration "aarch64-darwin";
      };
    };
}
