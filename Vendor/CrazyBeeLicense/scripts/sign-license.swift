#!/usr/bin/env swift
// Émet une licence CrazyBee signée (Ed25519), vérifiable hors-ligne par le kit.
//
//   swift scripts/sign-license.swift                       # universelle, à vie
//   swift scripts/sign-license.swift --apps "*" --sub "Jeremy"
//   swift scripts/sign-license.swift --apps company.lno.shotbox,company.lno.bulkrenamer --days 365 --sub "Client X"
//
// Clé privée lue depuis $CBL_KEY ou ~/crazybee-license-signing/owner_ed25519_private.key
import CryptoKit
import Foundation

func b64url(_ d: Data) -> String {
    d.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

var apps = ["*"]
var sub = "Crazy Bee Labs"
var exp: Double? = nil
var keyPath = ProcessInfo.processInfo.environment["CBL_KEY"]
    ?? FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("crazybee-license-signing/owner_ed25519_private.key").path

let args = Array(CommandLine.arguments.dropFirst())
var i = 0
while i < args.count {
    switch args[i] {
    case "--apps": i += 1; if i < args.count { apps = args[i].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
    case "--sub":  i += 1; if i < args.count { sub = args[i] }
    case "--days": i += 1; if i < args.count { exp = Date().addingTimeInterval((Double(args[i]) ?? 0) * 86_400).timeIntervalSince1970 }
    case "--key":  i += 1; if i < args.count { keyPath = args[i] }
    default: break
    }
    i += 1
}

guard
    let privB64 = try? String(contentsOfFile: keyPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
    let privData = Data(base64Encoded: privB64),
    let priv = try? Curve25519.Signing.PrivateKey(rawRepresentation: privData)
else {
    FileHandle.standardError.write(Data("❌ Clé privée introuvable/illisible : \(keyPath)\n".utf8))
    exit(1)
}

var payloadObj: [String: Any] = ["v": 1, "apps": apps, "sub": sub]
if let exp { payloadObj["exp"] = exp }
let payloadData = try! JSONSerialization.data(withJSONObject: payloadObj, options: [.sortedKeys])
let seg = b64url(payloadData)
let sig = try! priv.signature(for: Data(seg.utf8))
print("CBL1." + seg + "." + b64url(sig))
