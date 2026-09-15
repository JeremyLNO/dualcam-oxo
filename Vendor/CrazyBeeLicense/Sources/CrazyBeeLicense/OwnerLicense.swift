import Foundation
import CryptoKit

/// Vérification **hors-ligne** des licences « propriétaire » signées Ed25519.
///
/// Format de clé : `CBL1.<payload base64url>.<signature base64url>`
/// La signature est vérifiée avec la clé publique embarquée ci-dessous ; la clé
/// privée correspondante reste secrète (elle sert à émettre les licences).
///
/// Une licence peut cibler toutes les apps (`apps: ["*"]`, licence *universelle*)
/// ou un ou plusieurs bundle identifiers précis, avec une expiration optionnelle.
enum OwnerLicense {

    /// Clé publique Ed25519 (base64) — sûre à publier.
    static let publicKeyBase64 = "a9BGY2v6Rq83PqRmV6soW1/acRYUUEHzl2fBX6UtMlA="

    struct Verdict {
        var valid: Bool
        var validUntil: Date?   // nil == à vie
    }

    private struct Payload: Decodable {
        var v: Int
        var apps: [String]
        var exp: Double?        // epoch (s) ; absent == à vie
        var sub: String?
    }

    /// `nil` si `key` n'est **pas** un jeton propriétaire (→ validation serveur classique).
    /// Sinon, verdict tranché hors-ligne (signature + portée + expiration).
    static func verdict(for key: String, bundleId: String) -> Verdict? {
        guard key.hasPrefix("CBL1.") else { return nil }

        let parts = key.dropFirst(5).split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return Verdict(valid: false, validUntil: nil) }
        let payloadSeg = String(parts[0])

        guard
            let sigData = Self.decodeB64URL(String(parts[1])),
            let payloadData = Self.decodeB64URL(payloadSeg),
            let pubData = Data(base64Encoded: publicKeyBase64),
            let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: pubData),
            pub.isValidSignature(sigData, for: Data(payloadSeg.utf8)),
            let payload = try? JSONDecoder().decode(Payload.self, from: payloadData)
        else {
            return Verdict(valid: false, validUntil: nil)
        }

        // Portée : universelle ("*") ou bundleId précis
        guard payload.apps.contains("*") || payload.apps.contains(bundleId) else {
            return Verdict(valid: false, validUntil: nil)
        }

        // Expiration éventuelle
        if let exp = payload.exp {
            let until = Date(timeIntervalSince1970: exp)
            return Verdict(valid: until > Date(), validUntil: until)
        }
        return Verdict(valid: true, validUntil: nil)   // à vie
    }

    private static func decodeB64URL(_ s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+")
                 .replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b)
    }
}
