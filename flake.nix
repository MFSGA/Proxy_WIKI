{
  description = "proxy_wiki documentation development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      yapf3 = pkgs.writeShellScriptBin "yapf3" ''
        exec ${pkgs.python3Packages.yapf}/bin/yapf "$@"
      '';
      mkPwCommand = name: text:
        pkgs.writeShellScriptBin name ''
          set -euo pipefail
          repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
          cd "$repo_root"
          ${text}
        '';
      proxyWikiCommands = pkgs.symlinkJoin {
        name = "proxy-wiki-dev-commands";
        paths = [
          (pkgs.writeShellScriptBin "pw-help" ''
            cat <<'EOF'
          Proxy Wiki development commands:
            pw-serve [args...]      Preview English docs with cargo xtask serve
            pw-serve-zh [args...]   Preview Simplified Chinese docs
            pw-build [args...]      Build English docs
            pw-build-zh [args...]   Build Simplified Chinese docs
            pw-rust-test            Run mdBook code-block tests
            pw-test                 Run Rust workspace tests
            pw-clippy               Run Clippy with warnings denied
            pw-format               Format/check repository files with dprint and rustfmt
            pw-update-zh            Refresh po/zh-CN.po and print translation stats
            pw-check                Run the usual local validation sequence
          EOF
          '')
          (mkPwCommand "pw-serve" ''cargo xtask serve "$@"'')
          (mkPwCommand "pw-serve-zh" ''cargo xtask serve -l zh-CN "$@"'')
          (mkPwCommand "pw-build" ''cargo xtask build "$@"'')
          (mkPwCommand "pw-build-zh" ''cargo xtask build -l zh-CN "$@"'')
          (mkPwCommand "pw-rust-test" ''cargo xtask rust-tests'')
          (mkPwCommand "pw-test" ''cargo test'')
          (mkPwCommand "pw-clippy" ''cargo clippy -- -D warnings'')
          (mkPwCommand "pw-format" ''
            dprint fmt
            cargo fmt --all
          '')
          (mkPwCommand "pw-update-zh" ''scripts/update-zh.sh --stats'')
          (mkPwCommand "pw-check" ''
            cargo fmt --all -- --check
            dprint check
            cargo clippy -- -D warnings
            cargo test
            cargo xtask rust-tests
            cargo xtask build
          '')
        ];
      };
    in {
      devShells.${system}.default = pkgs.mkShell {
        nativeBuildInputs = with pkgs; [
          cargo
          rustc
          rustfmt
          clippy
          mdbook
          mdbook-i18n-helpers
          mdbook-mermaid
          mdbook-pandoc
          nodejs_22
          pnpm
          corepack
          python3
          git
          pkg-config
          openssl
          gettext
          dprint
          yapf3
          proxyWikiCommands
        ];

        shellHook = ''
          export CARGO_INSTALL_ROOT="$PWD/.cargo-tools"
          export PATH="$CARGO_INSTALL_ROOT/bin:$PATH"

          ensure_cargo_bin() {
            local bin="$1"
            local crate="$2"
            local version="$3"

            if ! command -v "$bin" >/dev/null 2>&1; then
              echo "Installing $crate $version into $CARGO_INSTALL_ROOT"
              cargo install "$crate" --version "$version" --locked
            fi
          }

          ensure_local_bin() {
            local bin="$1"
            local path="$2"

            if ! command -v "$bin" >/dev/null 2>&1; then
              echo "Installing $bin into $CARGO_INSTALL_ROOT"
              cargo install --path "$path" --locked
            fi
          }

          ensure_cargo_bin mdbook-svgbob mdbook-svgbob 0.2.2
          ensure_cargo_bin mdbook-linkcheck2 mdbook-linkcheck2 0.9.1
          ensure_local_bin mdbook-course ./mdbook-course
          ensure_local_bin mdbook-exerciser ./mdbook-exerciser

          echo "Proxy Wiki dev shell ready. Run 'pw-help' for commands."
        '';
      };
    };
}
