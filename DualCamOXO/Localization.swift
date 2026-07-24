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
        // License
        "license_feature_4k_title": [.en: "4K recording", .fr: "Enregistrement 4K", .es: "Grabación en 4K", .de: "4K-Aufnahme", .pt: "Gravação em 4K"],
        "license_feature_4k_detail": [.en: "Full 4K on both lenses, not just 1080p.", .fr: "4K complet sur les deux objectifs, pas juste 1080p.", .es: "4K completo en ambas lentes, no solo 1080p.", .de: "Volles 4K auf beiden Objektiven, nicht nur 1080p.", .pt: "4K completo em ambas as lentes, não só 1080p."],
        "license_feature_layouts_title": [.en: "Every layout", .fr: "Toutes les dispositions", .es: "Todos los formatos", .de: "Alle Layouts", .pt: "Todos os layouts"],
        "license_feature_layouts_detail": [.en: "Portrait+Landscape and Front+Back, combined or separate.", .fr: "Portrait+Paysage et Avant+Arrière, combinés ou séparés.", .es: "Vertical+Horizontal y Frontal+Trasera, combinadas o por separado.", .de: "Hoch+Quer und Vorne+Hinten, kombiniert oder getrennt.", .pt: "Retrato+Paisagem e Frontal+Traseira, combinadas ou separadas."],
        "license_feature_nowatermark_title": [.en: "No watermark", .fr: "Sans filigrane", .es: "Sin marca de agua", .de: "Kein Wasserzeichen", .pt: "Sem marca de água"],
        "license_feature_nowatermark_detail": [.en: "Clean exports, ready to share.", .fr: "Exports propres, prêts à partager.", .es: "Exportaciones limpias, listas para compartir.", .de: "Saubere Exporte, bereit zum Teilen.", .pt: "Exportações limpas, prontas a partilhar."],

        // Onboarding (first launch)
        "onboarding_trial_title": [.en: "Your 7-day free trial has started", .fr: "Votre essai gratuit de 7 jours a commencé", .es: "Tu prueba gratuita de 7 días ha comenzado", .de: "Deine 7-tägige kostenlose Testversion hat begonnen", .pt: "O seu período de teste gratuito de 7 dias começou"],
        "onboarding_trial_body": [.en: "Every feature is unlocked — no credit card, no payment info needed. Enjoy the full app for 7 days.", .fr: "Toutes les fonctionnalités sont débloquées — aucune carte bancaire, aucun paiement requis. Profitez de l'application complète pendant 7 jours.", .es: "Todas las funciones están desbloqueadas — sin tarjeta, sin datos de pago. Disfruta de la app completa durante 7 días.", .de: "Alle Funktionen sind freigeschaltet — keine Kreditkarte, keine Zahlungsdaten nötig. Genieße die volle App 7 Tage lang.", .pt: "Todas as funcionalidades estão desbloqueadas — sem cartão, sem dados de pagamento. Aproveite a app completa durante 7 dias."],
        "onboarding_get_started": [.en: "Get started", .fr: "Commencer", .es: "Empezar", .de: "Los geht's", .pt: "Começar"],

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
        "video": [.en: "Video", .fr: "Vidéo", .es: "Vídeo", .de: "Video", .pt: "Vídeo"],
        "photo": [.en: "Photo", .fr: "Photo", .es: "Foto", .de: "Foto", .pt: "Foto"],
        "saved_photo": [.en: "Saved to Photos", .fr: "Photo enregistrée", .es: "Foto guardada", .de: "Foto gesichert", .pt: "Foto guardada"],
        "stop": [.en: "Stop", .fr: "Arrêter", .es: "Detener", .de: "Stopp", .pt: "Parar"],
        "grid": [.en: "Grid", .fr: "Grille", .es: "Cuadrícula", .de: "Raster", .pt: "Grelha"],

        // Save mode
        "save_mode": [.en: "Save to Photos", .fr: "Enregistrer dans Photos", .es: "Guardar en Fotos", .de: "In Fotos sichern", .pt: "Guardar em Fotos"],
        "save_combined": [.en: "One combined video", .fr: "Une seule vidéo combinée", .es: "Un vídeo combinado", .de: "Ein kombiniertes Video", .pt: "Um vídeo combinado"],
        "save_separate": [.en: "Two separate videos", .fr: "Deux vidéos séparées", .es: "Dos vídeos separados", .de: "Zwei getrennte Videos", .pt: "Dois vídeos separados"],
        "save_combined_desc": [.en: "Both feeds stacked in a single clip.", .fr: "Les deux flux empilés dans un seul clip.", .es: "Ambas señales en un solo clip.", .de: "Beide Feeds in einem Clip.", .pt: "Ambos os sinais num único clipe."],
        "save_separate_desc": [.en: "Each feed saved as its own clip.", .fr: "Chaque flux enregistré séparément.", .es: "Cada señal como su propio clip.", .de: "Jeder Feed als eigener Clip.", .pt: "Cada sinal como o seu próprio clipe."],
        "combined_layout": [.en: "Combined layout", .fr: "Disposition combinée", .es: "Diseño combinado", .de: "Kombiniertes Layout", .pt: "Disposição combinada"],
        "layout_stacked": [.en: "Stacked", .fr: "Empilé", .es: "Apilado", .de: "Gestapelt", .pt: "Empilhado"],
        "layout_pip": [.en: "Picture-in-picture", .fr: "Incrusté (PiP)", .es: "Imagen en imagen", .de: "Bild-in-Bild", .pt: "Imagem na imagem"],
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
        "account_not_signed_in": [.en: "Not signed in", .fr: "Non connecté", .es: "No conectado", .de: "Nicht angemeldet", .pt: "Sessão não iniciada"],
        "account_manage": [.en: "Manage account", .fr: "Gérer le compte", .es: "Gestionar cuenta", .de: "Konto verwalten", .pt: "Gerir conta"],
        "account_title": [.en: "Account", .fr: "Compte", .es: "Cuenta", .de: "Konto", .pt: "Conta"],
        "account_intro": [.en: "Sign in to sync Pro across your devices.", .fr: "Connectez-vous pour synchroniser Pro sur vos appareils.", .es: "Inicia sesión para sincronizar Pro en tus dispositivos.", .de: "Melde dich an, um Pro geräteübergreifend zu synchronisieren.", .pt: "Inicie sessão para sincronizar o Pro entre dispositivos."],
        "sign_in_apple": [.en: "Sign in with Apple", .fr: "Se connecter avec Apple", .es: "Iniciar sesión con Apple", .de: "Mit Apple anmelden", .pt: "Iniciar sessão com a Apple"],
        "or_email": [.en: "or with email", .fr: "ou avec e-mail", .es: "o con correo", .de: "oder mit E-Mail", .pt: "ou com e-mail"],
        "email": [.en: "Email", .fr: "E-mail", .es: "Correo electrónico", .de: "E-Mail", .pt: "E-mail"],
        "password": [.en: "Password", .fr: "Mot de passe", .es: "Contraseña", .de: "Passwort", .pt: "Palavra-passe"],
        "sign_in": [.en: "Sign in", .fr: "Se connecter", .es: "Iniciar sesión", .de: "Anmelden", .pt: "Iniciar sessão"],
        "signing_in": [.en: "Signing in…", .fr: "Connexion…", .es: "Iniciando sesión…", .de: "Anmeldung…", .pt: "A iniciar sessão…"],
        "forgot_password": [.en: "Forgot password?", .fr: "Mot de passe oublié ?", .es: "¿Olvidaste tu contraseña?", .de: "Passwort vergessen?", .pt: "Esqueceu a palavra-passe?"],
        "forgot_password_sent": [.en: "If that email has an account, a reset link is on its way — check your inbox.", .fr: "Si ce compte existe, un lien de réinitialisation arrive — vérifiez vos e-mails.", .es: "Si esa cuenta existe, un enlace de restablecimiento está en camino — revisa tu correo.", .de: "Falls dieses Konto existiert, ist ein Reset-Link unterwegs — prüfe dein Postfach.", .pt: "Se essa conta existir, um link de reposição está a caminho — verifique o seu e-mail."],
        "no_account_yet": [.en: "New here? Create your account on the Crazy Bee Labs website.", .fr: "Nouveau ici ? Créez votre compte sur le site Crazy Bee Labs.", .es: "¿Nuevo por aquí? Crea tu cuenta en el sitio de Crazy Bee Labs.", .de: "Neu hier? Erstelle dein Konto auf der Crazy-Bee-Labs-Website.", .pt: "Novo por aqui? Crie a sua conta no site da Crazy Bee Labs."],
        "signed_in_as": [.en: "Signed in as", .fr: "Connecté en tant que", .es: "Conectado como", .de: "Angemeldet als", .pt: "Sessão iniciada como"],
        "sign_out": [.en: "Sign out", .fr: "Se déconnecter", .es: "Cerrar sesión", .de: "Abmelden", .pt: "Terminar sessão"],
        "danger_zone": [.en: "Danger zone", .fr: "Zone de danger", .es: "Zona de peligro", .de: "Gefahrenzone", .pt: "Zona de perigo"],
        "delete_account": [.en: "Delete my account", .fr: "Supprimer mon compte", .es: "Eliminar mi cuenta", .de: "Mein Konto löschen", .pt: "Eliminar a minha conta"],
        "delete_account_warning": [.en: "This permanently deletes your account and Pro entitlement link. This cannot be undone.", .fr: "Cela supprime définitivement votre compte et le lien vers votre achat Pro. Action irréversible.", .es: "Esto elimina permanentemente tu cuenta y el enlace a tu compra Pro. No se puede deshacer.", .de: "Dies löscht dein Konto und die Pro-Verknüpfung endgültig. Das kann nicht rückgängig gemacht werden.", .pt: "Isto elimina permanentemente a sua conta e a ligação à compra Pro. Não pode ser desfeito."],
        "delete_account_confirm_label": [.en: "Type DELETE to confirm", .fr: "Tapez DELETE pour confirmer", .es: "Escribe DELETE para confirmar", .de: "Gib DELETE ein, um zu bestätigen", .pt: "Digite DELETE para confirmar"],
        "delete_account_button": [.en: "Permanently delete my account", .fr: "Supprimer définitivement mon compte", .es: "Eliminar permanentemente mi cuenta", .de: "Mein Konto endgültig löschen", .pt: "Eliminar permanentemente a minha conta"],
        "deleting": [.en: "Deleting…", .fr: "Suppression…", .es: "Eliminando…", .de: "Wird gelöscht…", .pt: "A eliminar…"],
        "cancel_generic": [.en: "Cancel", .fr: "Annuler", .es: "Cancelar", .de: "Abbrechen", .pt: "Cancelar"],
        "privacy_policy": [.en: "Privacy Policy", .fr: "Politique de confidentialité", .es: "Política de privacidad", .de: "Datenschutzerklärung", .pt: "Política de privacidade"],

        // Pro / purchases
        "dualcam_pro": [.en: "DualCam OxO Pro", .fr: "DualCam OxO Pro", .es: "DualCam OxO Pro", .de: "DualCam OxO Pro", .pt: "DualCam OxO Pro"],
        "pro_title": [.en: "Unlock DualCam OxO Pro", .fr: "Débloquez DualCam OxO Pro", .es: "Desbloquea DualCam OxO Pro", .de: "DualCam OxO Pro freischalten", .pt: "Desbloqueie o DualCam OxO Pro"],
        "pro_lead": [.en: "One-time purchase. Yours forever, on all your devices.", .fr: "Achat unique. Définitivement à vous, sur tous vos appareils.", .es: "Compra única. Tuyo para siempre, en todos tus dispositivos.", .de: "Einmalkauf. Für immer deins, auf allen deinen Geräten.", .pt: "Compra única. Seu para sempre, em todos os dispositivos."],
        "pro_feature_4k": [.en: "Unlimited 4K recording", .fr: "Enregistrement 4K illimité", .es: "Grabación 4K ilimitada", .de: "Unbegrenzte 4K-Aufnahme", .pt: "Gravação 4K ilimitada"],
        "pro_feature_watermark": [.en: "Watermark-free combined exports", .fr: "Exports combinés sans filigrane", .es: "Exportaciones combinadas sin marca de agua", .de: "Kombinierte Exporte ohne Wasserzeichen", .pt: "Exportações combinadas sem marca de água"],
        "pro_unlock": [.en: "Unlock Pro", .fr: "Débloquer Pro", .es: "Desbloquear Pro", .de: "Pro freischalten", .pt: "Desbloquear Pro"],
        "pro_row_title": [.en: "DualCam OxO Pro", .fr: "DualCam OxO Pro", .es: "DualCam OxO Pro", .de: "DualCam OxO Pro", .pt: "DualCam OxO Pro"],
        "pro_row_active": [.en: "Unlocked", .fr: "Débloqué", .es: "Desbloqueado", .de: "Freigeschaltet", .pt: "Desbloqueado"],
        "restore_purchases": [.en: "Restore purchases", .fr: "Restaurer les achats", .es: "Restaurar compras", .de: "Käufe wiederherstellen", .pt: "Restaurar compras"],
        "restore_done": [.en: "Purchases restored", .fr: "Achats restaurés", .es: "Compras restauradas", .de: "Käufe wiederhergestellt", .pt: "Compras restauradas"],
        "restore_none": [.en: "No previous purchase found", .fr: "Aucun achat précédent trouvé", .es: "No se encontró ninguna compra anterior", .de: "Kein vorheriger Kauf gefunden", .pt: "Nenhuma compra anterior encontrada"],
        "locked_4k_hint": [.en: "4K is a Pro feature", .fr: "La 4K est une fonctionnalité Pro", .es: "4K es una función Pro", .de: "4K ist eine Pro-Funktion", .pt: "4K é uma funcionalidade Pro"],

        // Errors
        "err_offline": [.en: "You're offline. Check your connection and try again.", .fr: "Vous êtes hors ligne. Vérifiez votre connexion et réessayez.", .es: "Estás sin conexión. Comprueba tu conexión e inténtalo de nuevo.", .de: "Du bist offline. Verbindung prüfen und erneut versuchen.", .pt: "Está offline. Verifique a ligação e tente novamente."],
        "err_unauthorized": [.en: "Your session expired. Please sign in again.", .fr: "Votre session a expiré. Reconnectez-vous.", .es: "Tu sesión ha caducado. Vuelve a iniciar sesión.", .de: "Deine Sitzung ist abgelaufen. Bitte melde dich erneut an.", .pt: "A sua sessão expirou. Inicie sessão novamente."],
        "err_generic": [.en: "Something went wrong. Please try again.", .fr: "Une erreur s'est produite. Réessayez.", .es: "Algo salió mal. Inténtalo de nuevo.", .de: "Etwas ist schiefgelaufen. Bitte versuche es erneut.", .pt: "Algo correu mal. Tente novamente."],

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
