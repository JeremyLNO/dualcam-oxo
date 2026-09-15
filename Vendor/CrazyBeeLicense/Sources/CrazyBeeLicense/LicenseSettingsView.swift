import SwiftUI

// MARK: - LicenseSettingsView (compact — Settings tab)

/// The "License" section for an app's Settings window.
/// Shows validity status when licensed, otherwise a key field + "Buy" link.
public struct LicenseSettingsView: View {
    @ObservedObject private var manager: LicenseManager
    @State private var keyInput: String = ""
    @State private var error: String?
    @State private var working: Bool = false
    @Environment(\.openURL) private var openURL

    public init(manager: LicenseManager) {
        self.manager = manager
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusRow
            Divider()
            if case .licensed = manager.state {
                licensedControls
            } else {
                activationControls
            }
        }
        .frame(maxWidth: 460, alignment: .leading)
    }

    @ViewBuilder private var statusRow: some View {
        switch manager.state {
        case .trial(let days):
            row(CrazyBeeL.t("Free trial", "Essai gratuit", "Kostenlose Testversion", "Prueba gratuita", "Teste gratuito"),
                CrazyBeeL.daysLeft(days), .orange, "clock")
        case .licensed(let until):
            row(CrazyBeeL.t("Licensed", "Licence active", "Lizenziert", "Con licencia", "Com licença"),
                CrazyBeeL.validUntil(until.map { Self.df.string(from: $0) }),
                .green, "checkmark.seal.fill")
        case .expiredTrial:
            row(CrazyBeeL.t("Trial ended", "Essai terminé", "Testphase beendet", "Prueba finalizada", "Teste terminado"),
                CrazyBeeL.t("Enter a license to keep using the app.", "Entrez une licence pour continuer à utiliser l'app.", "Geben Sie eine Lizenz ein, um die App weiter zu nutzen.", "Introduce una licencia para seguir usando la app.", "Introduza uma licença para continuar a usar a app."),
                .red, "exclamationmark.triangle.fill")
        case .invalid(let reason):
            row(CrazyBeeL.statusReason(reason),
                CrazyBeeL.t("Renew or enter a valid license.", "Renouvelez ou entrez une licence valide.", "Erneuern Sie sie oder geben Sie eine gültige Lizenz ein.", "Renueva o introduce una licencia válida.", "Renove ou introduza uma licença válida."),
                .red, "xmark.seal.fill")
        }
    }

    private func row(_ title: String, _ subtitle: String, _ color: Color, _ symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if manager.isChecking { ProgressView().controlSize(.small) }
        }
    }

    private var activationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("CBL-XXXXX-XXXXX-XXXXX-XXXXX", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                Button(working ? CrazyBeeL.t("Checking…", "Vérification…", "Wird geprüft…", "Comprobando…", "A verificar…")
                               : CrazyBeeL.t("Activate", "Activer", "Aktivieren", "Activar", "Ativar")) {
                    Task { await activate() }
                }
                .disabled(working)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Button(CrazyBeeL.t("Buy a license", "Acheter une licence", "Lizenz kaufen", "Comprar una licencia", "Comprar uma licença")) {
                openURL(manager.purchaseURL)
            }
            .buttonStyleCompatLink()
        }
    }

    private var licensedControls: some View {
        HStack {
            Button(CrazyBeeL.t("Re-check now", "Revérifier maintenant", "Jetzt erneut prüfen", "Volver a comprobar", "Verificar novamente")) {
                Task { await manager.refresh() }
            }
            Spacer()
            Button(CrazyBeeL.t("Remove license", "Supprimer la licence", "Lizenz entfernen", "Eliminar licencia", "Remover licença"), role: .destructive) {
                manager.removeLicenseKey()
            }
        }
    }

    private func activate() async {
        guard !keyInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        working = true
        error = nil
        let ok = await manager.setLicenseKey(keyInput)
        working = false
        if ok {
            keyInput = ""
        } else if case .invalid(let r) = manager.state {
            error = CrazyBeeL.activationError(r)
        } else {
            error = CrazyBeeL.t("Couldn't verify that license. Check the key or your connection.", "Impossible de vérifier cette licence. Vérifiez la clé ou votre connexion.", "Diese Lizenz konnte nicht überprüft werden. Prüfen Sie den Schlüssel oder Ihre Verbindung.", "No se pudo verificar esa licencia. Comprueba la clave o tu conexión.", "Não foi possível verificar essa licença. Verifique a chave ou a sua ligação.")
        }
    }

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()
}

// MARK: - LicenseFeature

/// A marketing highlight shown as a card on the locked screen.
public struct LicenseFeature: Identifiable {
    public let id = UUID()
    public let systemImage: String
    public let title: String
    public let detail: String
    public init(systemImage: String, title: String, detail: String) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
    }
}

// MARK: - LicenseLockedView (full paywall)

/// Full-screen paywall shown when `manager.isFunctional == false` (trial ended / expired / blocked).
///
/// Layout (top to bottom):
///   1. Optional logo (passed by the app from its own bundle)
///   2. State icon + title + subtitle
///   3. Feature highlight cards (LazyVGrid, 3 columns max)
///   4. Primary "Get a license" CTA (honey amber, links to purchaseURL)
///   5. "crazybeelabs.com" link
///   6. "Already have a key?" + key field + Activate button
///
/// Usage:
/// ```swift
/// LicenseLockedView(
///     manager: AppLicense.manager,
///     features: [...],
///     labels: .init(buy: "Get FastRename"),
///     logo: Image(nsImage: NSImage(named: "CrazyBeeLabs") ?? NSImage())
/// )
/// ```
public struct LicenseLockedView: View {

    // MARK: Labels

    /// All user-visible strings — override to localise.
    public struct Labels {
        public var trialEndedTitle: String
        public var expiredTitle: String
        public var blockedTitle: String
        public var requiredTitle: String
        public var subtitle: String
        public var keyPlaceholder: String
        public var activate: String
        public var checking: String
        public var buy: String
        public var haveKey: String
        public var invalidKey: String

        public init(
            trialEndedTitle: String = CrazyBeeL.t("Your free trial has ended", "Votre essai gratuit est terminé", "Ihre kostenlose Testversion ist abgelaufen", "Tu prueba gratuita ha terminado", "O seu teste gratuito terminou"),
            expiredTitle: String = CrazyBeeL.t("Your license has expired", "Votre licence a expiré", "Ihre Lizenz ist abgelaufen", "Tu licencia ha caducado", "A sua licença expirou"),
            blockedTitle: String = CrazyBeeL.t("This license has been blocked", "Cette licence a été bloquée", "Diese Lizenz wurde gesperrt", "Esta licencia ha sido bloqueada", "Esta licença foi bloqueada"),
            requiredTitle: String = CrazyBeeL.t("A license is required", "Une licence est requise", "Eine Lizenz ist erforderlich", "Se requiere una licencia", "É necessária uma licença"),
            subtitle: String = CrazyBeeL.t("Unlock the full app — get a license or enter your key below.", "Débloquez l'app complète — obtenez une licence ou entrez votre clé ci-dessous.", "Schalten Sie die vollständige App frei — holen Sie sich eine Lizenz oder geben Sie unten Ihren Schlüssel ein.", "Desbloquea la app completa — consigue una licencia o introduce tu clave abajo.", "Desbloqueie a app completa — obtenha uma licença ou introduza a sua chave abaixo."),
            keyPlaceholder: String = "CBL-XXXXX-XXXXX-XXXXX",
            activate: String = CrazyBeeL.t("Activate", "Activer", "Aktivieren", "Activar", "Ativar"),
            checking: String = CrazyBeeL.t("Checking…", "Vérification…", "Wird geprüft…", "Comprobando…", "A verificar…"),
            buy: String = CrazyBeeL.t("Get a license on CrazyBeeLabs.com", "Obtenir une licence sur CrazyBeeLabs.com", "Lizenz auf CrazyBeeLabs.com erhalten", "Consigue una licencia en CrazyBeeLabs.com", "Obtenha uma licença em CrazyBeeLabs.com"),
            haveKey: String = CrazyBeeL.t("Already have a license key?", "Vous avez déjà une clé de licence ?", "Sie haben bereits einen Lizenzschlüssel?", "¿Ya tienes una clave de licencia?", "Já tem uma chave de licença?"),
            invalidKey: String = CrazyBeeL.t("That license couldn't be verified. Check the key or your connection.", "Cette licence n'a pas pu être vérifiée. Vérifiez la clé ou votre connexion.", "Diese Lizenz konnte nicht überprüft werden. Prüfen Sie den Schlüssel oder Ihre Verbindung.", "Esa licencia no pudo verificarse. Comprueba la clave o tu conexión.", "Não foi possível verificar essa licença. Verifique a chave ou a sua ligação.")
        ) {
            self.trialEndedTitle = trialEndedTitle
            self.expiredTitle = expiredTitle
            self.blockedTitle = blockedTitle
            self.requiredTitle = requiredTitle
            self.subtitle = subtitle
            self.keyPlaceholder = keyPlaceholder
            self.activate = activate
            self.checking = checking
            self.buy = buy
            self.haveKey = haveKey
            self.invalidKey = invalidKey
        }
    }

    // MARK: Properties

    @ObservedObject private var manager: LicenseManager
    private let features: [LicenseFeature]
    private let labels: Labels
    private let logo: Image?

    @State private var keyInput = ""
    @State private var error: String?
    @State private var working = false
    @Environment(\.openURL) private var openURL

    // CBL brand colours
    private static let honey = Color(red: 0.961, green: 0.706, blue: 0.0)   // #F5B400
    private static let amber = Color(red: 0.851, green: 0.604, blue: 0.0)   // #D99A00

    public init(
        manager: LicenseManager,
        features: [LicenseFeature] = [],
        labels: Labels = Labels(),
        logo: Image? = nil
    ) {
        self.manager = manager
        self.features = features
        self.labels = labels
        self.logo = logo
    }

    // MARK: Body

    public var body: some View {
        VStack(spacing: 0) {
            // Contenu marketing — défile si la fenêtre est vraiment trop courte.
            ScrollView {
                VStack(spacing: 16) {
                    headerSection
                    if !features.isEmpty { featuresSection }
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 22)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            Divider()
            // Zone d'action ÉPINGLÉE en bas — bouton d'achat + lien + champ licence,
            // toujours visibles sans scroller, quelle que soit la taille de fenêtre.
            ctaSection
                .padding(.horizontal, 36)
                .padding(.vertical, 16)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Logo from the host app's bundle
            if let logo {
                logo
                    .resizable()
                    .scaledToFit()
                    .frame(height: 34)
                    .opacity(0.85)
            }

            // State icon
            ZStack {
                Circle()
                    .fill(stateColor.opacity(0.12))
                    .frame(width: 46, height: 46)
                Image(systemName: stateIcon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(stateColor)
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                Text(labels.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
        }
    }

    // MARK: - Feature cards

    private var featuresSection: some View {
        let colCount = min(features.count, 3)
        let cols = Array(repeating: GridItem(.flexible(), spacing: 12), count: colCount)
        return LazyVGrid(columns: cols, spacing: 12) {
            ForEach(features) { featureCard($0) }
        }
    }

    private func featureCard(_ f: LicenseFeature) -> some View {
        VStack(spacing: 8) {
            Image(systemName: f.systemImage)
                .font(.system(size: 22))
                .foregroundStyle(Self.honey)
                .frame(height: 28)
            Text(f.title)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(f.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .top)
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.quaternary.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Self.honey.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 12) {
            // Primary buy button — honey amber
            Button {
                openURL(manager.purchaseURL)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "cart.fill")
                    Text(labels.buy).fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .tint(Self.honey)
            .controlSize(.large)
            .frame(maxWidth: 440)

            // Explicit site link
            Button {
                openURL(URL(string: "https://crazybeelabs.com")!)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "globe")
                    Text("crazybeelabs.com")
                }
            }
            .buttonStyleCompatLink()
            .font(.caption)
            .foregroundStyle(.secondary)

            // "Already have a key?" separator
            HStack(spacing: 12) {
                Rectangle().frame(height: 1).foregroundStyle(.quaternary)
                Text(labels.haveKey)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize()
                Rectangle().frame(height: 1).foregroundStyle(.quaternary)
            }
            .frame(maxWidth: 440)
            .padding(.top, 4)

            // Key field + Activate
            HStack(spacing: 8) {
                TextField(labels.keyPlaceholder, text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                Button(working ? labels.checking : labels.activate) {
                    Task { await activate() }
                }
                .disabled(working)
            }
            .frame(maxWidth: 440)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
        }
    }

    // MARK: - Helpers

    private var title: String {
        switch manager.state {
        case .expiredTrial: return labels.trialEndedTitle
        case .invalid(let r):
            switch r {
            case "blocked": return labels.blockedTitle
            case "expired": return labels.expiredTitle
            default: return labels.requiredTitle
            }
        default: return labels.requiredTitle
        }
    }

    private var stateIcon: String {
        switch manager.state {
        case .expiredTrial: return "clock.badge.xmark"
        case .invalid(let r):
            switch r {
            case "blocked": return "xmark.shield.fill"
            case "expired": return "calendar.badge.minus"
            default: return "lock.fill"
            }
        default: return "lock.fill"
        }
    }

    private var stateColor: Color {
        switch manager.state {
        case .expiredTrial: return .orange
        case .invalid(let r):
            switch r {
            case "blocked", "revoked", "expired": return .red
            default: return .secondary
            }
        default: return .secondary
        }
    }

    private func activate() async {
        guard !keyInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        working = true
        error = nil
        let ok = await manager.setLicenseKey(keyInput)
        working = false
        if ok { keyInput = "" } else { error = labels.invalidKey }
    }
}

// MARK: - Shared helpers

private extension View {
    @ViewBuilder func buttonStyleCompatLink() -> some View {
#if os(macOS)
        self.buttonStyle(.link)
#else
        self.buttonStyle(.borderless)
#endif
    }
}
