import Foundation

/// Supported in-app languages.
/// Default = the system language when supported, else English.
/// The user's explicit choice (Settings) is persisted and always wins.
enum AppLanguage: String, CaseIterable, Identifiable {
    case en, fr, es, de, pt
    var id: String { rawValue }

    var flag: String {
        switch self {
        case .en: return "🇬🇧"
        case .fr: return "🇫🇷"
        case .es: return "🇪🇸"
        case .de: return "🇩🇪"
        case .pt: return "🇵🇹"
        }
    }

    /// Endonym (language name written in that language).
    var name: String {
        switch self {
        case .en: return "English"
        case .fr: return "Français"
        case .es: return "Español"
        case .de: return "Deutsch"
        case .pt: return "Português"
        }
    }

    static let storageKey = "app.language"

    /// The best default derived from the system, falling back to English.
    static var systemDefault: AppLanguage {
        for code in Locale.preferredLanguages {
            let base = code.split(separator: "-").first.map(String.init)?.lowercased() ?? ""
            if let match = AppLanguage(rawValue: base) { return match }
        }
        return .en
    }

    /// The language actually in effect: the user's saved choice, else the system default.
    /// The saved choice takes priority over the default.
    static var current: AppLanguage {
        if let raw = UserDefaults.standard.string(forKey: storageKey),
           let lang = AppLanguage(rawValue: raw) {
            return lang
        }
        return systemDefault
    }
}

/// Tiny in-app localization table (key → per-language string).
/// Missing keys fall back to English, then to the key itself.
enum L {
    static func t(_ key: String, _ lang: AppLanguage = .current) -> String {
        table[key]?[lang] ?? table[key]?[.en] ?? key
    }

    static let table: [String: [AppLanguage: String]] = [
        // App
        "app_name": [.en: "DualCam OxO", .fr: "DualCam OxO", .es: "DualCam OxO", .de: "DualCam OxO", .pt: "DualCam OxO"],
        "app_tagline": [.en: "Two lenses. One take.", .fr: "Deux objectifs. Une prise.", .es: "Dos lentes. Una toma.", .de: "Zwei Linsen. Eine Aufnahme.", .pt: "Duas lentes. Uma captura."],

        // Capture modes
        "mode_orientation": [.en: "Portrait + Landscape", .fr: "Portrait + Paysage", .es: "Vertical + Horizontal", .de: "Hoch + Quer", .pt: "Retrato + Paisagem"],
        "mode_frontback": [.en: "Front + Back", .fr: "Avant + Arrière", .es: "Frontal + Trasera", .de: "Front + Rück", .pt: "Frontal + Traseira"],
        "mode": [.en: "Mode", .fr: "Mode", .es: "Modo", .de: "Modus", .pt: "Modo"],
        "camera_side": [.en: "Camera", .fr: "Caméra", .es: "Cámara", .de: "Kamera", .pt: "Câmara"],
        "side_back": [.en: "Back", .fr: "Arrière", .es: "Trasera", .de: "Rück", .pt: "Traseira"],
        "side_front": [.en: "Front", .fr: "Avant", .es: "Frontal", .de: "Front", .pt: "Frontal"],
        "swap": [.en: "Swap", .fr: "Inverser", .es: "Intercambiar", .de: "Tauschen", .pt: "Trocar"],
        "label_portrait": [.en: "Portrait", .fr: "Portrait", .es: "Vertical", .de: "Hoch", .pt: "Retrato"],
        "label_landscape": [.en: "Landscape", .fr: "Paysage", .es: "Horizontal", .de: "Quer", .pt: "Paisagem"],

        // Quality
        "quality": [.en: "Quality", .fr: "Qualité", .es: "Calidad", .de: "Qualität", .pt: "Qualidade"],
        "quality_720": [.en: "HD · 720p", .fr: "HD · 720p", .es: "HD · 720p", .de: "HD · 720p", .pt: "HD · 720p"],
        "quality_1080": [.en: "Full HD · 1080p", .fr: "Full HD · 1080p", .es: "Full HD · 1080p", .de: "Full HD · 1080p", .pt: "Full HD · 1080p"],
        "quality_4k": [.en: "4K · UHD", .fr: "4K · UHD", .es: "4K · UHD", .de: "4K · UHD", .pt: "4K · UHD"],

        // On-screen controls
        "flash": [.en: "Flash", .fr: "Flash", .es: "Flash", .de: "Blitz", .pt: "Flash"],
        "flash_on": [.en: "Flash on", .fr: "Flash activé", .es: "Flash activado", .de: "Blitz an", .pt: "Flash ligado"],
        "flash_off": [.en: "Flash off", .fr: "Flash désactivé", .es: "Flash apagado", .de: "Blitz aus", .pt: "Flash desligado"],
        "record": [.en: "Record", .fr: "Enregistrer", .es: "Grabar", .de: "Aufnehmen", .pt: "Gravar"],
        "stop": [.en: "Stop", .fr: "Arrêter", .es: "Detener", .de: "Stopp", .pt: "Parar"],
        "grid": [.en: "Grid", .fr: "Grille", .es: "Cuadrícula", .de: "Raster", .pt: "Grelha"],

        // Save mode
        "save_mode": [.en: "Save to Photos", .fr: "Enregistrer dans Photos", .es: "Guardar en Fotos", .de: "In Fotos sichern", .pt: "Guardar em Fotos"],
        "save_combined": [.en: "One combined video", .fr: "Une seule vidéo combinée", .es: "Un vídeo combinado", .de: "Ein kombiniertes Video", .pt: "Um vídeo combinado"],
        "save_separate": [.en: "Two separate videos", .fr: "Deux vidéos séparées", .es: "Dos vídeos separados", .de: "Zwei getrennte Videos", .pt: "Dois vídeos separados"],
        "save_combined_desc": [.en: "Both feeds stacked in a single clip.", .fr: "Les deux flux empilés dans un seul clip.", .es: "Ambas señales en un solo clip.", .de: "Beide Feeds in einem Clip.", .pt: "Ambos os sinais num único clipe."],
        "save_separate_desc": [.en: "Each feed saved as its own clip.", .fr: "Chaque flux enregistré séparément.", .es: "Cada señal como su propio clip.", .de: "Jeder Feed als eigener Clip.", .pt: "Cada sinal como o seu próprio clipe."],
        "saving": [.en: "Saving…", .fr: "Enregistrement…", .es: "Guardando…", .de: "Sichern…", .pt: "A guardar…"],
        "saved": [.en: "Saved to Photos", .fr: "Enregistré dans Photos", .es: "Guardado en Fotos", .de: "In Fotos gesichert", .pt: "Guardado em Fotos"],
        "save_failed": [.en: "Couldn't save video", .fr: "Échec de l'enregistrement", .es: "No se pudo guardar", .de: "Speichern fehlgeschlagen", .pt: "Falha ao guardar"],

        // Settings
        "settings": [.en: "Settings", .fr: "Réglages", .es: "Ajustes", .de: "Einstellungen", .pt: "Definições"],
        "done": [.en: "Done", .fr: "OK", .es: "Listo", .de: "Fertig", .pt: "Concluído"],
        "general": [.en: "General", .fr: "Général", .es: "General", .de: "Allgemein", .pt: "Geral"],
        "set_language": [.en: "Language", .fr: "Langue", .es: "Idioma", .de: "Sprache", .pt: "Idioma"],
        "set_grid": [.en: "Composition grid", .fr: "Grille de composition", .es: "Cuadrícula de composición", .de: "Kompositionsraster", .pt: "Grelha de composição"],
        "set_default_quality": [.en: "Default quality", .fr: "Qualité par défaut", .es: "Calidad predeterminada", .de: "Standardqualität", .pt: "Qualidade padrão"],
        "capture_section": [.en: "Capture", .fr: "Capture", .es: "Captura", .de: "Aufnahme", .pt: "Captura"],
        "notif_section": [.en: "Notifications", .fr: "Notifications", .es: "Notificaciones", .de: "Mitteilungen", .pt: "Notificações"],
        "set_notifications": [.en: "Allow notifications", .fr: "Autoriser les notifications", .es: "Permitir notificaciones", .de: "Mitteilungen erlauben", .pt: "Permitir notificações"],
        "set_notifications_desc": [.en: "Tips, news and update alerts.", .fr: "Astuces, actus et alertes de mise à jour.", .es: "Consejos, novedades y avisos de actualización.", .de: "Tipps, News und Update-Hinweise.", .pt: "Dicas, novidades e avisos de atualização."],
        "check_updates": [.en: "Check for updates", .fr: "Rechercher des mises à jour", .es: "Buscar actualizaciones", .de: "Nach Updates suchen", .pt: "Procurar atualizações"],
        "up_to_date": [.en: "You're up to date", .fr: "Vous êtes à jour", .es: "Estás al día", .de: "Alles aktuell", .pt: "Está atualizado"],
        "update_available": [.en: "Update available", .fr: "Mise à jour disponible", .es: "Actualización disponible", .de: "Update verfügbar", .pt: "Atualização disponível"],

        // Account / registration
        "account_section": [.en: "Account", .fr: "Compte", .es: "Cuenta", .de: "Konto", .pt: "Conta"],
        "create_account": [.en: "Create a Crazy Bee Labs account", .fr: "Créer un compte Crazy Bee Labs", .es: "Crear una cuenta Crazy Bee Labs", .de: "Crazy-Bee-Labs-Konto erstellen", .pt: "Criar conta Crazy Bee Labs"],
        "create_account_desc": [.en: "Sync your preferences and get early features.", .fr: "Synchronisez vos préférences et accédez aux nouveautés.", .es: "Sincroniza tus preferencias y accede a novedades.", .de: "Einstellungen synchronisieren und Neues zuerst testen.", .pt: "Sincronize as preferências e receba novidades primeiro."],

        // About / support / signature
        "about": [.en: "About", .fr: "À propos", .es: "Acerca de", .de: "Über", .pt: "Sobre"],
        "support": [.en: "Support & ideas", .fr: "Support et idées", .es: "Soporte e ideas", .de: "Support & Ideen", .pt: "Suporte e ideias"],
        "version": [.en: "Version", .fr: "Version", .es: "Versión", .de: "Version", .pt: "Versão"],
        "rate_app": [.en: "Rate DualCam OxO", .fr: "Noter DualCam OxO", .es: "Valorar DualCam OxO", .de: "DualCam OxO bewerten", .pt: "Avaliar DualCam OxO"],

        // Review prompt (24h)
        "review_title": [.en: "Enjoying DualCam OxO?", .fr: "Vous aimez DualCam OxO ?", .es: "¿Te gusta DualCam OxO?", .de: "Gefällt dir DualCam OxO?", .pt: "A gostar do DualCam OxO?"],
        "review_body": [.en: "Your feedback helps us make it better.", .fr: "Votre avis nous aide à l'améliorer.", .es: "Tu opinión nos ayuda a mejorar.", .de: "Dein Feedback hilft uns.", .pt: "A sua opinião ajuda-nos a melhorar."],
        "review_yes": [.en: "Yes, I like it", .fr: "Oui, j'aime", .es: "Sí, me gusta", .de: "Ja, gefällt mir", .pt: "Sim, gosto"],
        "review_no": [.en: "Not really", .fr: "Pas vraiment", .es: "No mucho", .de: "Nicht wirklich", .pt: "Nem por isso"],

        // Permissions / states
        "cam_denied_title": [.en: "Camera access needed", .fr: "Accès caméra requis", .es: "Se necesita la cámara", .de: "Kamerazugriff nötig", .pt: "Acesso à câmara necessário"],
        "cam_denied_body": [.en: "Enable camera and microphone access in Settings to record.", .fr: "Activez l'accès caméra et micro dans Réglages pour filmer.", .es: "Activa la cámara y el micrófono en Ajustes para grabar.", .de: "Kamera- und Mikrofonzugriff in den Einstellungen aktivieren.", .pt: "Ative a câmara e o microfone nas Definições para gravar."],
        "open_settings": [.en: "Open Settings", .fr: "Ouvrir Réglages", .es: "Abrir Ajustes", .de: "Einstellungen öffnen", .pt: "Abrir Definições"],
        "multicam_unsupported": [.en: "This device can't run two cameras at once.", .fr: "Cet appareil ne peut pas filmer avec deux caméras.", .es: "Este dispositivo no admite dos cámaras a la vez.", .de: "Dieses Gerät unterstützt keine zwei Kameras gleichzeitig.", .pt: "Este dispositivo não suporta duas câmaras ao mesmo tempo."],
        "simulator_note": [.en: "Camera preview is unavailable in the Simulator.", .fr: "L'aperçu caméra est indisponible dans le simulateur.", .es: "La vista previa no está disponible en el simulador.", .de: "Kameravorschau im Simulator nicht verfügbar.", .pt: "A pré-visualização não está disponível no simulador."],
    ]
}
