import Foundation

// 빌드할 때 비밀 파일에서 채워 둔 암호를 앱이 읽습니다.
// 키 값은 이 파일에 적지 않습니다. 설정 화면에서 받지 않습니다.

struct SecretPair {
    var mapbox: String
    var gemini: String
    var dataGoKr: String
}

enum SecretVault {
    static func load() -> SecretPair {
        SecretPair(
            mapbox: BakedSecrets.mapbox,
            gemini: BakedSecrets.gemini,
            dataGoKr: BakedSecrets.dataGoKr
        )
    }
}
