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
          };
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
            neovim # For testing the plugin
            luarocks # Lua package manager
            gnumake # For running the Makefile

            # Formatting tools (via treefmt-nix)
            treefmt.config.build.wrapper
          ];
        };
      }
    );
}
