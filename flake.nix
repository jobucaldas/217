{
  description = "217 development tools (lock inputs before validation)";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.rust-overlay.url = "github:oxalica/rust-overlay";
  inputs.rust-overlay.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    { nixpkgs, rust-overlay, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
    {
      devShells = nixpkgs.lib.genAttrs systems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ rust-overlay.overlays.default ];
          };
          rust = pkgs.rust-bin.stable.latest.default.override {
            extensions = [
              "rustfmt"
              "clippy"
            ];
            targets = [ "wasm32-unknown-unknown" ];
          };
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              go_1_25
              rust
              nodejs
              chromium
              playwright-driver.browsers
              postgresql_16
              caddy
              pkg-config
              openssl
              curl
              unzip
            ];
            PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
            PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH = "${pkgs.chromium}/bin/chromium";
            shellHook = ''
              export PATH="$PWD/.dev-tools/bin:$PATH"
              echo '217: run dev/nix-setup.sh once for wasm-bindgen-cli 0.2.121 and npm dependencies.'
            '';
          };
        }
      );
    };
}
