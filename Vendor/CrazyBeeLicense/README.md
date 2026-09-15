# CrazyBeeLicense

Drop-in licensing + trial for Crazy Bee Labs macOS apps. Pairs with the
`/api/licenses/validate` endpoint on CrazyBeeLabs.com (the source of truth).

- **7-day free trial** from the install date.
- **License entry** + background validation against the website.
- **Expiry enforced locally** (cached `validUntil`); a **block** (non-payment) applies
  the next time the server is reachable. Offline use keeps the last good state, so a
  network blip never disables the app.

Built & verified with `swift build` (macOS 13+, no external dependencies).

## Add it to an app

In the app's `Package.swift`:

```swift
dependencies: [
  .package(path: "../crazybee-license-kit"),        // local
  // or: .package(url: "https://github.com/JeremyLNO/crazybee-license-kit", branch: "main")
],
targets: [
  .executableTarget(name: "YourApp", dependencies: [
    .product(name: "CrazyBeeLicense", package: "crazybee-license-kit"),
  ]),
]
```

## Wire it up

```swift
import SwiftUI
import CrazyBeeLicense

@main
struct ShotboxApp: App {
  @StateObject private var license = LicenseManager(config: .init(
    apiBaseURL: URL(string: "https://crazybeelabs.com")!,
    bundleId: Bundle.main.bundleIdentifier ?? "company.lno.shotbox",
    purchaseURL: URL(string: "https://crazybeelabs.com/apps/shotbox")!
  ))
  @Environment(\.scenePhase) private var phase

  var body: some Scene {
    WindowGroup {
      Group {
        if license.isFunctional {
          ContentView()                         // your app
        } else {
          LicenseLockedView(manager: license)   // trial over / blocked / expired
        }
      }
      .task { license.startMonitoring() }
      .onChange(of: phase) { _, new in
        if new == .active { Task { await license.refresh() } }
      }
    }

    Settings {
      // … your settings …
      LicenseSettingsView(manager: license)     // the "License" section
    }
  }
}
```

That's the whole contract:
- **`license.isFunctional`** — gate features on this (true during trial or with a valid license).
- **`LicenseSettingsView`** — shows the current validity + date, or a key field + buy link.
- **`LicenseLockedView`** — optional full-window lock when not functional.

`State`: `.trial(daysLeft:)`, `.licensed(validUntil:)` (nil = lifetime), `.expiredTrial`,
`.invalid(reason:)`.

## Sparkle (auto-updates) — separate from licensing

Updates are handled by [Sparkle](https://sparkle-project.org), independent of the license:

1. Add Sparkle: `.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")`.
2. In `Info.plist`: `SUFeedURL` = your appcast (e.g. `https://crazybeelabs.com/appcast/shotbox.xml`),
   and `SUPublicEDKey` (from Sparkle's `generate_keys`).
3. Drive it from the app:

   ```swift
   import Sparkle
   let updater = SPUStandardUpdaterController(startingUpdater: true,
                                              updaterDelegate: nil, userDriverDelegate: nil)
   // a "Check for Updates…" menu item calls updater.updater.checkForUpdates()
   ```
4. Release flow: build + sign the `.app`, zip it, `sign_update` the zip, and publish the
   zip + an updated `appcast.xml` to the feed URL (host on the website or any static host).

So: **CrazyBeeLicense** decides *whether the app runs*; **Sparkle** keeps it *up to date*.

## Owner / universal licenses (offline, signed)

Besides server-validated keys, the kit accepts **offline Ed25519-signed licenses**
(`OwnerLicense.swift`). A key looks like `CBL1.<payload>.<signature>` and is verified
locally against the embedded public key — **no network needed**, works on macOS **and iOS**.
Use these for the owner/developer, review copies, or offline customers.

A payload targets one or more apps (`apps: ["*"]` = every app) with an optional expiry
(absent = lifetime). The signature is checked before the app trusts it, so keys can't be forged
without the private key.

**Issue a license** (private key stays secret, never in the repo):

```bash
swift scripts/sign-license.swift                                 # universal, lifetime
swift scripts/sign-license.swift --sub "Client X" --days 365     # all apps, 1 year
swift scripts/sign-license.swift --apps company.lno.shotbox --sub "Client Y"
```

The private key is read from `$CBL_KEY` or `~/crazybee-license-signing/owner_ed25519_private.key`.
The matching **public** key is embedded in `OwnerLicense.publicKeyBase64` (safe to publish).
Rotating the keypair only requires regenerating it and updating that one constant.
