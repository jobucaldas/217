{
  description = "217 development tools (lock inputs before validation)";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
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
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              go_1_26
              nodejs
              postgresql_16
              caddy
              pkg-config
              openssl
              curl
              unzip
            ];
            shellHook = ''
              echo '217: prefer container targets (make test / make mobile-apk). Host installs are not required.'
            '';
          };
        }
      );
    };
}
