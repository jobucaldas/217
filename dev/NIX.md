# Nix notes

Containers remain the supported path (`make test-backend`, `make test-mobile`, `make mobile-apk`).
The optional `flake.nix` provides a thin Go/Postgres/Caddy shell for contributors who already use Nix; it does **not** install Flutter on the host.

```sh
nix --extra-experimental-features "nix-command flakes" develop path:.
```

Flutter Android builds must still use the Flutter container image via `make mobile-apk`.
