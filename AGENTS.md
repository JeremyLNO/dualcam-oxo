# AGENTS.md — DualCam OxO (dual-lens iOS camera)

À lire avant toute modification. Fige comment on travaille sur **DualCam OxO**.

## Le projet
- App iOS native **SwiftUI**, filme avec **deux objectifs en même temps** (`AVCaptureMultiCamSession`).
- Deux modes :
  - **Portrait + Paysage** (`.orientation`) — deux objectifs du *même* côté (arrière ou avant) :
    grand-angle + ultra grand-angle (repli téléobjectif), un cadré 16:9, l'autre 9:16.
  - **Avant + Arrière** (`.frontBack`) — caméra frontale et arrière simultanément.
- **Layout PiP** : le flux principal remplit l'écran, le secondaire flotte dans un cadre
  (déplaçable). Défaut = mode **Portrait+Paysage** (portrait plein écran + cadre paysage 16:9).
  En Avant+Arrière : arrière plein écran + cadre portrait 9:16 « Avant ». **Sélecteur de mode**
  en bas (`SegmentedPills`) : les 2 modes toujours visibles, l'actif en **miel** (charte CBL).
- **Tap sur le cadre PiP = permute** principal/secondaire (`swapped`). **Pinch = zoom**, **tap = mise
  au point/expo** (réticule miel) sur le flux principal.
- **Photo / Vidéo** : bascule en bas (`CaptureKind`). Photo = double `AVCapturePhotoOutput` multi-cam.
- À l'écran : sélecteur de **qualité** (720p/1080p/4K), **flash** (torche). Réglages : **grille**.
- Enregistrement dans Photos : **1 média combiné** (empilé **ou incrusté PiP**, `CombinedLayout`)
  ou **2 médias séparés** — pour vidéos ET photos.
- Dossier local : `~/dualcam-oxo/`. Mono-target, bundle `company.lno.dualcamoxo`, **iOS 17+**,
  Swift 5 mode, team `2E6D4Q69QB`, iPhone uniquement, portrait.

## Compiler & lancer
- `./build-run.sh` — build simulateur, boot, install, lancement.
- `./build-run.sh -demoLang fr` — force la langue. `-demoMode <orientation|frontBack>` — force le mode.
  `-forceReview` — affiche le prompt d'avis. `-openSettings` — ouvre les réglages.
- Ou Xcode : ouvrir `DualCamOXO.xcodeproj`, scheme **DualCamOXO**, ⌘R.
- ⚠️ **Le multi-cam ne marche QUE sur un iPhone réel.** Dans le simulateur (aucune caméra),
  l'app tourne avec des aperçus « placeholder » → l'UI, les réglages, les langues et le prompt
  d'avis sont testables, mais **pas** la capture/enregistrement.
- Multi-cam nécessite un appareil compatible (iPhone XS/XR et +). `AVCaptureMultiCamSession.isMultiCamSupported`
  garde le tout ; sinon l'écran affiche un message et ne plante pas.

## Architecture
- **DualCamOXOApp.swift** — `@main` + `AppDelegate`. Stampe la date d'installation (avis),
  configure les notifications, lance un check de mise à jour au démarrage.
- **Palette.swift** — tokens noir + miel (charte Crazy Bee Labs).
- **Localization.swift** — table in-code `L.t(key, lang)` EN/FR/ES/DE/PT. Défaut = langue système,
  repli anglais ; le choix utilisateur (persisté sous `app.language`) est **prioritaire**.
- **Components.swift** — `AppInfo` (URLs support/site/compte, `appStoreID`), UI réutilisable.
- **CameraModels.swift** — enums `CaptureMode`, `CameraSide`, `VideoQuality`, `SaveMode`,
  `CaptureKind` (photo/vidéo), `CombinedLayout` (empilé/incrusté PiP).
- **AppSettings.swift** — préférences **versionnées** (`schemaVersion`, migration **non destructive**)
  persistées dans UserDefaults. Singleton `.shared`.
- **CameraEngine.swift** — moteur multi-cam : inputs sans connexion + ports exposés pour l'aperçu,
  data outputs (vidéo) **ou** `AVCapturePhotoOutput` (photo) selon `kind`, torche, **zoom/mise au point**
  par device, enregistrement via deux `FeedWriter`, capture photo via `DualPhotoCapture` (2 stills →
  1 callback). Dégrade proprement (simu/denied/unsupported).
- **FeedWriter.swift** — un `AVAssetWriter` par flux (vidéo + audio partagé), thread-safe.
- **VideoComposer.swift** — combine deux clips (empilé ou **incrusté PiP**, `AVMutableVideoComposition`)
  et compose deux photos (`UIGraphicsImageRenderer`) ; sauvegarde dans Photos (`PHPhotoLibrary`)
  selon `SaveMode` + `CombinedLayout`.
- **CameraPreview.swift** — `AVCaptureVideoPreviewLayer` par port (multi-cam) + placeholder + grille.
- **CameraView.swift** — écran principal : flux principal plein écran + PiP flottant déplaçable,
  contrôles, bouton record. `FeedPreview` prend un `rotationAngle` (90 portrait / 0 paysage).
- **SettingsView.swift** — grille, save mode, qualité, langue, notifications, inscription, support,
  signature CBL (logo + lien).
- **ReviewManager.swift** / **ReviewPromptView.swift** — prompt **24 h après install** :
  Oui → note App Store · Non → page support.
- **NotificationService.swift** — notifications locales + **OneSignal** (point d'intégration) +
  détection de mise à jour via iTunes lookup. **OneSignalBridge.swift** — guardé `#if canImport`.
- **Keychain.swift** — wrapper Keychain minimal pour le jeton de session (jamais dans UserDefaults).
- **NetworkMonitor.swift** — `NWPathMonitor` singleton (`isOnline`) ; toutes les vues réseau affichent
  un état « hors ligne » propre plutôt qu'un spinner infini ou un crash.
- **APIClient.swift** — client JSON générique vers l'API `crazybeelabs.com` (`AppInfo.apiBaseURL`),
  `APIError` (offline/server/unauthorized/decoding) toujours traduit via `L.t`.
- **AccountManager.swift** — état de session (`.shared`) : Sign in with Apple natif
  (`completeAppleSignIn`, piloté par `SignInWithAppleButton` côté vue), email/mot de passe,
  reset password, suppression de compte (appelle `DELETE /api/account`), déconnexion. Jeton en
  Keychain, cache utilisateur non sensible en UserDefaults.
- **AccountView.swift** — écran Compte (sheet) : état déconnecté (Apple + email/mdp + mot de passe
  oublié + lien inscription web) / connecté (e-mail, zone de danger suppression avec confirmation
  « DELETE »). Bannière hors-ligne via `NetworkMonitor`.
- **PurchaseManager.swift** — StoreKit 2, produit non-consommable `AppInfo.proProductID`
  (`company.lno.dualcamoxo.pro`). `isPro` dérivé de `Transaction.currentEntitlements` ; Restore
  Purchases = `AppStore.sync()`. Aucune dépendance backend (source de vérité = StoreKit).
- **PaywallView.swift** — sheet « DualCam OxO Pro » (4K illimité + export combiné sans filigrane),
  bouton d'achat (prix StoreKit live) + Restore Purchases.
- **Gating Pro** : 4K verrouillé (`CameraView.selectQuality`/`SettingsView.qualityBinding` ouvrent
  le paywall au lieu d'appliquer 4K sans Pro ; `effectiveQuality` re-garde côté moteur au cas où
  l'entitlement change). Filigrane « DualCam OxO » sur les exports **combinés** uniquement
  (`VideoComposer`, `watermarked:` — CALayer/`AVVideoCompositionCoreAnimationTool` pour la vidéo,
  dessin Core Graphics pour la photo) ; les exports séparés (flux bruts) ne sont jamais filigranés.

## Conventions
- `project.pbxproj` **écrit à la main**, schéma d'UUID lisible : `AA…` projet/groupes · `BB…` target ·
  `CC…` produit · `DD…` config lists · `EE…` build configs · `FF…` build phases ·
  `AC…` file refs · `BA…` build files. Ajouter un fichier = 1 `PBXFileReference` + entrée groupe
  `DualCamOXO` + 1 `PBXBuildFile` + entrée dans `Sources`.

## À compléter avant publication (placeholders)
1. **App Store ID** — `AppInfo.appStoreID` dans `Components.swift` (actuellement `0000000000`).
   Débloque le lien d'avis App Store et le check de mise à jour iTunes.
2. **OneSignal** — ajouter le package SPM `OneSignalXCFramework`
   (https://github.com/OneSignal/OneSignal-iOS-SDK) à la target, puis renseigner
   `NotificationService.oneSignalAppID`. Le code s'active tout seul (`#if canImport(OneSignalFramework)`).
   Les messages + deep links (dont « mise à jour disponible ») s'écrivent dans le dashboard OneSignal ;
   un push peut porter `additionalData["url"]` pour ouvrir une page.
3. **aps-environment** — `DualCamOXO.entitlements` est en `development` ; passer en `production` pour la prod.
4. **Sign In with Apple (portail Apple Developer)** — activer la capability « Sign In with Apple »
   sur l'App ID `company.lno.dualcamoxo` (developer.apple.com → Certificates, Identifiers & Profiles).
   L'entitlement `com.apple.developer.applesignin` est déjà dans `DualCamOXO.entitlements` ; sans
   l'activation portail, le bouton natif échoue sur device.
5. **App Store Connect — produit Pro** — créer l'achat intégré **non-consommable** avec l'identifiant
   exact `company.lno.dualcamoxo.pro` (`AppInfo.proProductID`). Sans lui, `PurchaseManager` ne trouve
   aucun produit et le bouton d'achat reste désactivé (Restore Purchases reste fonctionnel).
6. **Backend crazybeelabs-app** — le compte in-app (Sign in with Apple, reset password, suppression)
   appelle `AppInfo.apiBaseURL` (crazybeelabs.com/api). Voir `~/crazybeelabs-app/AGENTS.md` (ou le
   commit correspondant) : nécessite la migration `drizzle/0005_account_apple.sql` appliquée en base
   avant que ces écrans fonctionnent en prod.

## Compat & données
- Toutes les préférences passent par `AppSettings` (UserDefaults, clés stables) avec un `schemaVersion`.
  Une future version migre via `migrateIfNeeded()` **sans jamais effacer** les valeurs existantes.
- Les vidéos vivent dans Photos (l'app n'a pas de base à migrer).

## Git
- Commit après chaque lot ; message terminé par `Co-Authored-By: Claude Opus 4.8 …`.
