import Foundation

// 이미 계산된 숫자와 채비를 인공지능에게 넘겨, 오늘 순서 문장만 다듬게 합니다.
// 새 숫자, 새 고기, 새 조황을 지어내지 말라고 못 박습니다.

enum BriefingClient {
    static func rewrite(script: String, apiKey: String) async throws -> String {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw BriefingError.missingKey }
        let models = ["gemini-3.8-flash", "gemini-2.5-flash"]
        var lastError: Error = BriefingError.empty
        for model in models {
            do {
                return try await call(model: model, script: script, apiKey: key)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func call(model: String, script: String, apiKey: String) async throws -> String {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw BriefingError.empty
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 40
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let instruction = """
        너는 한국 낚시 현장 안내자다. 사용자가 준 계산 결과만 보고 오늘 출조 순서를 다듬어라.
        수온, 시각, 호수, 무게, 물고기 이름, 장소 이름을 바꾸거나 새로 만들지 마라.
        조황, 씨알, 마릿수는 자료에 없으면 절대 말하지 마라.
        위험한 바람, 파도, 천둥이 있으면 첫 문장에서 나가지 말라고 하라.
        소제목은 정확히 이 네 개만 써라: 결론 / 오늘 순서 / 채비 이유 / 바꾸면 안 되는 것
        초보가 가방을 싸고 그 시간에 그 자리에 설 수 있게 짧게 써라.
        """
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": instruction]]],
            "contents": [["role": "user", "parts": [["text": script]]]],
            "generationConfig": ["temperature": 0.3, "maxOutputTokens": 1200],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BriefingError.rejected
        }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = object?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        let text = parts?.compactMap { $0["text"] as? String }.joined(separator: "\n") ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BriefingError.empty }
        return trimmed
    }
}

enum BriefingError: LocalizedError {
    case missingKey
    case rejected
    case empty

    var errorDescription: String? {
        switch self {
        case .missingKey: return "인공지능 암호가 없습니다."
        case .rejected: return "인공지능 연결이 거절되었습니다. 암호를 확인하세요."
        case .empty: return "인공지능이 빈 답을 보냈습니다. 계산된 순서를 그대로 쓰면 됩니다."
        }
    }
}
