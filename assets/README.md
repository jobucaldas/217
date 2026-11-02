# Store listing assets

Graphics for the Google Play store listing, one folder per Play Console section.

| Folder | Play Console section | Size |
| --- | --- | --- |
| `app-icon/` | App icon | 512 x 512 PNG |
| `feature-graphic/` | Feature graphic | 1024 x 500 PNG (`feature-graphic.svg` is the source) |
| `phone-screenshots/<locale>/` | Phone screenshots | 1080 x 1920 PNG |
| `tablet-7in-screenshots/<locale>/` | 7-inch tablet screenshots | 1080 x 1920 PNG |

Locales: `en-US` (default), `pt-BR`, `es-419`. Screenshots are numbered in the order they should be uploaded.

The app icon's source is `frontend/branding/app-icon.svg`; the launcher, web, Linux and Windows icons are rendered from it.

Screenshots are real app screens rendered with sample data (no personal data). Regenerate them with `./render-screenshots.sh` (needs podman or docker, or Flutter on `PATH`); the scenes live in `frontend/tool/store_screenshots_test.dart`.

On a pull request that changes the app's screens (`frontend/lib`, the fonts, `pubspec`, or this tooling), CI re-renders them and pushes a `chore(assets): re-render store screenshots` commit to the branch. That commit starts no new CI run, never repeats for a head the bot authored, and PRs from forks are skipped. The sample data is relative to today's date, so a re-render changes the files slightly (dates, message times); commit them yourself only when a scene changed.

The app has no tablet or desktop layout yet, so there are no 10-inch, desktop or Android XR sets.
