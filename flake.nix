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
            stylua.enable = true;
            nixpkgs-fmt.enable = true;
            prettier.enable = true;
            shfmt.enable = true;
            actionlint.enable = true;
            zizmor.enable = true;
            shellcheck.enable = true;
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
            lua5_1
            luajitPackages.luacheck
            luajitPackages.busted
            luajitPackages.luacov

            ast-grep
            neovim
            luarocks
            gnumake
            websocat
            jq

            treefmt.config.build.wrapper
          ];
        };
      }
    );
}
