{
  description = "proxy_wiki documentation development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
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
        '';
      };
    };
}
