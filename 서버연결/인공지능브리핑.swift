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

    /// 공개 글과 공개 포인트 목록만 보고, 괜찮은 자리의 이름과 위치 단서를 고릅니다.
    /// 좌표는 받지 않습니다. 위치는 목록의 번호이거나, 자료에 적힌 지명입니다.
    static func readMentions(script: String, apiKey: String) async throws -> [MentionDraft] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !script.isEmpty else { throw BriefingError.missingKey }
        let instruction = """
        너는 기준점 일대의 공개 자료만 읽는다.
        낚시 글로 괜찮은 포인트가 언급되거나, 공개 포인트 정보가 낚시 자리로 보이면 그것만 고른다.
        자료에 없는 장소, 좌표, 어종, 조황, 날씨, 물때는 만들지 마라.
        위도, 경도, 숫자의 좌표는 절대 쓰지 마라.
        위치를 자료 안에서 못 정하면 그 항목은 빼라.
        글에 나온 지명을 우선 고르고, 공개 포인트 목록에 같은 곳이 있으면 그 번호를 써라.
        최대 10개만 써라.
        각 항목은 아래 형식만 써라.
        SPOT
        이름: (자료에 있는 이름)
        근거: (자료에 있는 짧은 구절)
        위치종류: POINT 또는 PLACE
        위치값: POINT면 목록의 P번호만. PLACE면 자료 문장에 그대로 있는 지명만.
        END
        """
        let models = ["gemini-3.8-flash", "gemini-2.5-flash"]
        var lastError: Error = BriefingError.empty
        for model in models {
            do {
                let text = try await callRaw(model: model, script: script, instruction: instruction, apiKey: key, maxTokens: 2200)
                let parsed = parseMentions(text)
                if !parsed.isEmpty { return parsed }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// 이미 계산된 사실만 받아 추천 이유 문장을 다듬습니다. 순위와 숫자는 바꾸지 않습니다.
    static func polishFacts(_ blocks: [(id: String, text: String)], apiKey: String) async throws -> [String: String] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !blocks.isEmpty else { throw BriefingError.missingKey }
        let body = blocks.map { "ID: \($0.id)\n\($0.text)" }.joined(separator: "\n\n")
        let instruction = """
        너는 문장만 다듬는다. 각 블록의 사실만 보고 추천 이유를 두세 문장으로 써라.
        새 숫자, 새 어종, 새 장소, 새 마을어장, 새 금지구역, 새 사고, 새 금어기를 만들지 마라.
        제한을 피해서 들어가는 방법은 쓰지 마라.
        사실에 없는 내용은 쓰지 마라.
        블록마다 아래 형식만 써라.
        ID: (받은 ID 그대로)
        문장: (다듬은 문장)
        """
        let models = ["gemini-3.8-flash", "gemini-2.5-flash"]
        var lastError: Error = BriefingError.empty
        for model in models {
            do {
                let text = try await callRaw(model: model, script: body, instruction: instruction, apiKey: key, maxTokens: 2400)
                let parsed = parseFacts(text)
                if !parsed.isEmpty { return parsed }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func call(model: String, script: String, apiKey: String) async throws -> String {
        let instruction = """
        너는 한국 낚시 현장 안내자다. 사용자가 준 계산 결과만 보고 오늘 출조 순서를 다듬어라.
        수온, 시각, 호수, 무게, 물고기 이름, 장소 이름을 바꾸거나 새로 만들지 마라.
        조황, 씨알, 마릿수는 자료에 없으면 절대 말하지 마라.
        위험한 바람, 파도, 천둥이 있으면 첫 문장에서 나가지 말라고 하라.
        소제목은 정확히 이 네 개만 써라: 결론 / 오늘 순서 / 채비 이유 / 바꾸면 안 되는 것
        초보가 가방을 싸고 그 시간에 그 자리에 설 수 있게 짧게 써라.
        """
        return try await callRaw(model: model, script: script, instruction: instruction, apiKey: apiKey)
    }

    private static func callRaw(model: String, script: String, instruction: String, apiKey: String, maxTokens: Int = 1200) async throws -> String {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw BriefingError.empty
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 40
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": instruction]]],
            "contents": [["role": "user", "parts": [["text": script]]]],
            "generationConfig": ["temperature": 0.3, "maxOutputTokens": maxTokens],
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

    private static func parseFacts(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var current: String?
        var sentence = ""
        func commit() {
            let cleaned = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if let current, !cleaned.isEmpty { result[current] = cleaned }
            sentence = ""
        }
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("ID:") {
                commit()
                current = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("문장:") {
                sentence = String(line.dropFirst(3))
            } else if current != nil, !line.isEmpty {
                sentence = sentence.isEmpty ? line : sentence + " " + line
            }
        }
        commit()
        return result
    }

    private static func parseMentions(_ text: String) -> [MentionDraft] {
        var drafts: [MentionDraft] = []
        for rawBlock in text.components(separatedBy: "SPOT").dropFirst() {
            let body = rawBlock.components(separatedBy: "END").first ?? rawBlock
            var name = ""
            var basis = ""
            var kind = ""
            var value = ""
            for raw in body.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "*", with: "")
                if line.hasPrefix("이름:") {
                    name = cleaned(line, prefix: "이름:")
                } else if line.hasPrefix("근거:") {
                    basis = cleaned(line, prefix: "근거:")
                } else if line.hasPrefix("위치종류:") {
                    kind = cleaned(line, prefix: "위치종류:")
                } else if line.hasPrefix("위치값:") {
                    value = cleaned(line, prefix: "위치값:")
                } else if line.hasPrefix("위치:") {
                    let rest = cleaned(line, prefix: "위치:")
                    if rest.hasPrefix("POINT") {
                        kind = "POINT"
                        value = rest.replacingOccurrences(of: "POINT", with: "").trimmingCharacters(in: .whitespaces)
                    } else if rest.hasPrefix("PLACE") {
                        kind = "PLACE"
                        value = rest.replacingOccurrences(of: "PLACE", with: "").trimmingCharacters(in: .whitespaces)
                    }
                }
            }
            let draft = MentionDraft(name: name, basis: basis, kind: kind, value: value)
            if draft.usable { drafts.append(draft) }
            if drafts.count >= 10 { break }
        }
        return drafts
    }

    private static func cleaned(_ line: String, prefix: String) -> String {
        line.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MentionDraft {
    var name: String
    var basis: String
    var kind: String
    var value: String

    var usable: Bool {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count >= 1 else { return false }
        let upper = kind.uppercased()
        return upper.contains("POINT") || upper.contains("PLACE")
    }

    var isPoint: Bool { kind.uppercased().contains("POINT") }
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
