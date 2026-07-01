# DualCam OxO

Film with **two iPhone lenses at once**. A Crazy Bee Labs app.

- **Portrait + Landscape** — two lenses on the same side (back or front), one framed 16:9, one 9:16.
- **Front + Back** — record the front and back cameras together.
- On-screen: quality (720p / 1080p / 4K), flash. Settings: composition grid.
- Save to Photos as **one combined video** (feeds stacked) or **two separate videos**.

## Run

```bash
./build-run.sh                 # build + launch on the iOS Simulator
./build-run.sh -demoLang fr    # force a language
./build-run.sh -forceReview    # show the 24h review prompt now
./build-run.sh -openSettings   # open Settings
```

> Multi-cam capture only works on a real iPhone (XS/XR or newer). In the Simulator the app
> runs with placeholder feeds so the UI, settings, languages and review flow are testable.

## Features

- **Languages** — English, French, Spanish, German, Portuguese. Defaults to the system language,
  falls back to English, and remembers the user's explicit choice (which always wins).
- **Reviews** — 24h after install: “Enjoying DualCam OxO?” → **Yes** opens the App Store rating page,
  **No** opens the Support & ideas page.
- **Notifications** — via [OneSignal](https://onesignal.com) (customizable messages + deep links,
  including an “update available” campaign), plus a local update check.
- **Account** — a link to create a Crazy Bee Labs account.
- **Upgrade-safe** — versioned settings with non-destructive migration; no data loss between releases.
- **Signature** — Crazy Bee Labs logo + site link at the bottom of Settings.

## Before shipping

See `AGENTS.md` → *À compléter avant publication*: set `AppInfo.appStoreID`, add the OneSignal SPM
package + `oneSignalAppID`, and switch `aps-environment` to `production`.
