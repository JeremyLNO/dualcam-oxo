# AGENTS.md — DualCam OxO (dual-lens iOS camera)

À lire avant toute modification. Fige comment on travaille sur **DualCam OxO**.

## Le projet
- App iOS native **SwiftUI**, filme avec **deux objectifs en même temps** (`AVCaptureMultiCamSession`).
- Deux modes :
  - **Portrait + Paysage** (`.orientation`) — deux objectifs du *même* côté (arrière ou avant) :
    grand-angle + ultra grand-angle (repli téléobjectif), un cadré 16:9, l'autre 9:16.
  - **Avant + Arrière** (`.frontBack`) — caméra frontale et arrière simultanément.
- À l'écran : sélecteur de **qualité** (720p/1080p/4K), **flash** (torche). Réglages : **grille**.
- Enregistrement dans Photos : **1 vidéo combinée** (flux empilés) ou **2 vidéos séparées**.
- Dossier local : `~/dualcam-oxo/`. Mono-target, bundle `company.lno.dualcamoxo`, **iOS 17+**,
  Swift 5 mode, team `2E6D4Q69QB`, iPhone uniquement, portrait.

## Compiler & lancer
- `./build-run.sh` — build simulateur, boot, install, lancement.
- `./build-run.sh -demoLang fr` — force la langue. `-forceReview` — affiche le prompt d'avis.
  `-openSettings` — ouvre les réglages.
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
- **CameraModels.swift** — enums `CaptureMode`, `CameraSide`, `VideoQuality`, `SaveMode`.
- **AppSettings.swift** — préférences **versionnées** (`schemaVersion`, migration **non destructive**)
  persistées dans UserDefaults. Singleton `.shared`.
- **CameraEngine.swift** — moteur multi-cam : inputs sans connexion + ports exposés pour l'aperçu,
  data outputs + torche, enregistrement via deux `FeedWriter`. Dégrade proprement (simu/denied/unsupported).
- **FeedWriter.swift** — un `AVAssetWriter` par flux (vidéo + audio partagé), thread-safe.
- **VideoComposer.swift** — combine deux clips (empilés, canvas portrait, `AVMutableVideoComposition`)
  et sauvegarde dans Photos (`PHPhotoLibrary`) selon `SaveMode`.
- **CameraPreview.swift** — `AVCaptureVideoPreviewLayer` par port (multi-cam) + placeholder + grille.
- **CameraView.swift** — écran principal (2 aperçus empilés, contrôles, bouton record).
- **SettingsView.swift** — grille, save mode, qualité, langue, notifications, inscription, support,
  signature CBL (logo + lien).
- **ReviewManager.swift** / **ReviewPromptView.swift** — prompt **24 h après install** :
  Oui → note App Store · Non → page support.
- **NotificationService.swift** — notifications locales + **OneSignal** (point d'intégration) +
  détection de mise à jour via iTunes lookup. **OneSignalBridge.swift** — guardé `#if canImport`.

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

## Compat & données
- Toutes les préférences passent par `AppSettings` (UserDefaults, clés stables) avec un `schemaVersion`.
  Une future version migre via `migrateIfNeeded()` **sans jamais effacer** les valeurs existantes.
- Les vidéos vivent dans Photos (l'app n'a pas de base à migrer).

## Git
- Commit après chaque lot ; message terminé par `Co-Authored-By: Claude Opus 4.8 …`.
