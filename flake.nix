{
  description = "Claude Code Neovim plugin development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs = { self, nixpkgs, flake-utils, treefmt-nix, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        treefmt = treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs = {
            stylua.enable = true; # Lua formatter
            nixpkgs-fmt.enable = true; # Nix formatter
            prettier.enable = true; # Markdown/YAML/JSON formatter
            shfmt.enable = true; # Shell formatter
            actionlint.enable = true; # GitHub Actions linter
            zizmor.enable = true; # GitHub Actions security analyzer
            shellcheck.enable = true; # Shell script analyzer
          };
          settings.formatter.shellcheck.options = [ "--exclude=SC1091,SC2016" ];
        };
      in
      {
        # Format the source tree
        formatter = treefmt.config.build.wrapper;

        # Check formatting
        checks.formatting = treefmt.config.build.check self;

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Lua and development tools
            lua5_1
            luajitPackages.luacheck
            luajitPackages.busted # Testing framework

            # WebSocket implementation
            luajitPackages.luasocket
            luajitPackages.lua-cjson

            # Development utilities
            ast-grep
            neovim # For testing the plugin
            luarocks # Lua package manager
            gnumake # For running the Makefile
            websocat # WebSocket testing utility
            jq # JSON processor for parsing responses

            # Formatting tools (via treefmt-nix)
            treefmt.config.build.wrapper
          ];
        };
      }
    );
}
