import Foundation

// MARK: - Languages

/// Same 5 languages and raw values as every Crazy Bee Labs app, so a host app can bridge its own
/// language enum with `CBLLanguage(rawValue: hostLanguage.rawValue)`.
public enum CBLLanguage: String, CaseIterable, Identifiable, Sendable {
    case en, fr, de, es, pt
    public var id: String { rawValue }
}

/// Self-contained EN/FR/DE/ES/PT localization for the license UI, independent of any host app.
///
/// Host apps should keep this in sync with their own language setting:
/// ```swift
/// var language: AppLanguage {
///     didSet { L.current = language; CrazyBeeL.current = CBLLanguage(rawValue: language.rawValue) ?? .en }
/// }
/// ```
/// Left unsynced, it falls back to the system's preferred language.
public enum CrazyBeeL {
    public nonisolated(unsafe) static var current: CBLLanguage = systemDefault()

    public static func systemDefault() -> CBLLanguage {
        for pref in Locale.preferredLanguages {
            let code = pref.split(separator: "-").first.map { $0.lowercased() } ?? ""
            if let lang = CBLLanguage(rawValue: code) { return lang }
        }
        return .en
    }

    public static func t(_ en: String, _ fr: String) -> String {
        switch current {
        case .en: return en
        case .fr: return fr
        default: return table[en]?[current] ?? en
        }
    }

    public static func t(_ en: String, _ fr: String, _ de: String, _ es: String, _ pt: String) -> String {
        switch current {
        case .en: en
        case .fr: fr
        case .de: de
        case .es: es
        case .pt: pt
        }
    }

    // MARK: Pluralized / composed helpers (kept out of the flat table below)

    /// "3 days left" — correctly pluralized per language.
    public static func daysLeft(_ days: Int) -> String {
        switch current {
        case .en: "\(days) day\(days == 1 ? "" : "s") left"
        case .fr: "\(days) jour\(days == 1 ? "" : "s") restant\(days == 1 ? "" : "s")"
        case .de: "Noch \(days) Tag\(days == 1 ? "" : "e")"
        case .es: "\(days) día\(days == 1 ? "" : "s") restante\(days == 1 ? "" : "s")"
        case .pt: "\(days) dia\(days == 1 ? "" : "s") restante\(days == 1 ? "" : "s")"
        }
    }

    /// "Valid until <date>" / "Lifetime license" when `until` is nil.
    public static func validUntil(_ until: String?) -> String {
        guard let until else {
            return t("Lifetime license", "Licence à vie", "Lebenslange Lizenz", "Licencia de por vida", "Licença vitalícia")
        }
        return t("Valid until \(until)", "Valide jusqu'au \(until)", "Gültig bis \(until)", "Válida hasta \(until)", "Válida até \(until)")
    }

    /// "License expired" / "License blocked" / … — one grammatically-whole phrase per reason
    /// (not a concatenation of "License" + a translated adjective, which breaks word order in FR/DE/ES/PT).
    public static func statusReason(_ reason: String) -> String {
        switch reason {
        case "not_found": return t("License not recognised", "Licence non reconnue", "Lizenz nicht erkannt", "Licencia no reconocida", "Licença não reconhecida")
        case "wrong_app":  return t("License for another app", "Licence pour une autre app", "Lizenz für eine andere App", "Licencia para otra app", "Licença para outra app")
        case "blocked":    return t("License blocked", "Licence bloquée", "Lizenz gesperrt", "Licencia bloqueada", "Licença bloqueada")
        case "expired":    return t("License expired", "Licence expirée", "Lizenz abgelaufen", "Licencia caducada", "Licença expirada")
        case "revoked":    return t("License revoked", "Licence révoquée", "Lizenz widerrufen", "Licencia revocada", "Licença revogada")
        default:           return t("License invalid", "Licence invalide", "Lizenz ungültig", "Licencia no válida", "Licença inválida")
        }
    }

    /// "That license is expired." / … — full sentence per reason, same rationale as `statusReason`.
    public static func activationError(_ reason: String) -> String {
        switch reason {
        case "not_found": return t("That license is not recognised.", "Cette licence n'est pas reconnue.", "Diese Lizenz wird nicht erkannt.", "Esa licencia no se reconoce.", "Essa licença não é reconhecida.")
        case "wrong_app":  return t("That license is for another app.", "Cette licence est pour une autre app.", "Diese Lizenz gilt für eine andere App.", "Esa licencia es para otra app.", "Essa licença é para outra app.")
        case "blocked":    return t("That license is blocked.", "Cette licence est bloquée.", "Diese Lizenz ist gesperrt.", "Esa licencia está bloqueada.", "Essa licença está bloqueada.")
        case "expired":    return t("That license is expired.", "Cette licence est expirée.", "Diese Lizenz ist abgelaufen.", "Esa licencia ha caducado.", "Essa licença expirou.")
        case "revoked":    return t("That license is revoked.", "Cette licence est révoquée.", "Diese Lizenz wurde widerrufen.", "Esa licencia ha sido revocada.", "Essa licença foi revogada.")
        default:           return t("That license is invalid.", "Cette licence est invalide.", "Diese Lizenz ist ungültig.", "Esa licencia no es válida.", "Essa licença é inválida.")
        }
    }

    // MARK: Table DE/ES/PT (key = exact English string)

    private static let table: [String: [CBLLanguage: String]] = [
        "Free trial": [.de: "Kostenlose Testversion", .es: "Prueba gratuita", .pt: "Teste gratuito"],
        "Licensed": [.de: "Lizenziert", .es: "Con licencia", .pt: "Com licença"],
        "Trial ended": [.de: "Testphase beendet", .es: "Prueba finalizada", .pt: "Teste terminado"],
        "Enter a license to keep using the app.": [.de: "Geben Sie eine Lizenz ein, um die App weiter zu nutzen.", .es: "Introduce una licencia para seguir usando la app.", .pt: "Introduza uma licença para continuar a usar a app."],
        "Renew or enter a valid license.": [.de: "Erneuern Sie sie oder geben Sie eine gültige Lizenz ein.", .es: "Renueva o introduce una licencia válida.", .pt: "Renove ou introduza uma licença válida."],
        "Checking…": [.de: "Wird geprüft…", .es: "Comprobando…", .pt: "A verificar…"],
        "Activate": [.de: "Aktivieren", .es: "Activar", .pt: "Ativar"],
        "Buy a license": [.de: "Lizenz kaufen", .es: "Comprar una licencia", .pt: "Comprar uma licença"],
        "Couldn't verify that license. Check the key or your connection.": [.de: "Diese Lizenz konnte nicht überprüft werden. Prüfen Sie den Schlüssel oder Ihre Verbindung.", .es: "No se pudo verificar esa licencia. Comprueba la clave o tu conexión.", .pt: "Não foi possível verificar essa licença. Verifique a chave ou a sua ligação."],
        "Re-check now": [.de: "Jetzt erneut prüfen", .es: "Volver a comprobar", .pt: "Verificar novamente"],
        "Remove license": [.de: "Lizenz entfernen", .es: "Eliminar licencia", .pt: "Remover licença"],
        "Your free trial has ended": [.de: "Ihre kostenlose Testversion ist abgelaufen", .es: "Tu prueba gratuita ha terminado", .pt: "O seu teste gratuito terminou"],
        "Your license has expired": [.de: "Ihre Lizenz ist abgelaufen", .es: "Tu licencia ha caducado", .pt: "A sua licença expirou"],
        "This license has been blocked": [.de: "Diese Lizenz wurde gesperrt", .es: "Esta licencia ha sido bloqueada", .pt: "Esta licença foi bloqueada"],
        "A license is required": [.de: "Eine Lizenz ist erforderlich", .es: "Se requiere una licencia", .pt: "É necessária uma licença"],
        "Unlock the full app — get a license or enter your key below.": [.de: "Schalten Sie die vollständige App frei — holen Sie sich eine Lizenz oder geben Sie unten Ihren Schlüssel ein.", .es: "Desbloquea la app completa — consigue una licencia o introduce tu clave abajo.", .pt: "Desbloqueie a app completa — obtenha uma licença ou introduza a sua chave abaixo."],
        "Get a license on CrazyBeeLabs.com": [.de: "Lizenz auf CrazyBeeLabs.com erhalten", .es: "Consigue una licencia en CrazyBeeLabs.com", .pt: "Obtenha uma licença em CrazyBeeLabs.com"],
        "Already have a license key?": [.de: "Sie haben bereits einen Lizenzschlüssel?", .es: "¿Ya tienes una clave de licencia?", .pt: "Já tem uma chave de licença?"],
        "That license couldn't be verified. Check the key or your connection.": [.de: "Diese Lizenz konnte nicht überprüft werden. Prüfen Sie den Schlüssel oder Ihre Verbindung.", .es: "Esa licencia no pudo verificarse. Comprueba la clave o tu conexión.", .pt: "Não foi possível verificar essa licença. Verifique a chave ou a sua ligação."],
    ]
}
