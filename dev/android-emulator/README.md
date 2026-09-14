# Android emulator harness

Container-only Android Web Push validation for 217.

## What it does

- runs Nix inside a rootless Podman container only;
- provisions an x86_64 `google_apis_playstore` emulator image with KVM;
- uses `adb reverse` so Android Chrome can open `http://localhost:8080`;
- grants Chrome notification permission at the Android app-op layer;
- drives Chrome over CDP with Playwright when available;
- records Android screenshots and bounded logs under `artifacts/android/`.

## Reproduction

1. Refresh the web stack with VAPID enabled:

```sh
make dev-down
make vapid-keys > .env.reminders.local
make dev-up
```

2. Run the Android validation from the repo root:

```sh
dev/android-emulator/run.sh validate
```

3. Optional interactive emulator session:

```sh
dev/android-emulator/run.sh start
```

## Cleanup

```sh
dev/android-emulator/run.sh cleanup || true
make dev-down
rm -f .env.reminders.local
rm -rf artifacts/android
```

## Limitations

- The emulator image is large and the first Nix build can take several minutes.
- The harness depends on Chrome + Google Play Services shipping in the selected image; if either is missing, the run fails closed.
- Current validated image path is `system-images;android-34-ext12;google_apis_playstore;x86_64`.
- `adb reverse` only makes localhost work inside the emulator; production still needs trusted HTTPS.
- Web Push on Android is still best-effort and can be delayed by Play Services, Chrome, or Doze.
