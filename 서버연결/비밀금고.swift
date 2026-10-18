import Foundation
import Security

// 지도 암호와 인공지능 암호를 열쇠고에 넣습니다.
// 프로그램 명령어 안에 암호를 적지 않습니다.

struct SecretPair {
    var mapbox: String
    var gemini: String
}

enum SecretVault {
    private static let service = "바로낚시"

    static func load() -> SecretPair {
        let saved = SecretPair(mapbox: read("mapbox") ?? "", gemini: read("gemini") ?? "")
        if !saved.mapbox.isEmpty || !saved.gemini.isEmpty {
            return saved
        }
        if let imported = readSecretsFile() {
            save(imported)
            return imported
        }
        return SecretPair(mapbox: "", gemini: "")
    }

    static func save(_ pair: SecretPair) {
        write("mapbox", pair.mapbox)
        write("gemini", pair.gemini)
    }

    static func parse(_ text: String) -> SecretPair {
        var mapbox = ""
        var gemini = ""
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "MAPBOX_ACCESS_TOKEN": mapbox = parts[1]
            case "GEMINI_API_KEY": gemini = parts[1]
            default: break
            }
        }
        return SecretPair(mapbox: mapbox, gemini: gemini)
    }

    private static func readSecretsFile() -> SecretPair? {
        for path in candidatePaths() {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let pair = parse(text)
            if !pair.mapbox.isEmpty || !pair.gemini.isEmpty { return pair }
        }
        return nil
    }

    private static func candidatePaths() -> [String] {
        var paths: [String] = []
        if let env = ProcessInfo.processInfo.environment["BARO_NAKSI_SECRETS_PATH"], !env.isEmpty {
            paths.append(env)
        }
        #if os(macOS)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        paths.append("\(home)/fishing_hint/비밀암호/비밀암호.txt")
        #endif
        return paths
    }

    private static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    private static func write(_ account: String, _ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var query = base
        query[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }
}
