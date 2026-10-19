import Foundation

// 로그인 없이 누구나 볼 수 있는 낚시 글만 가져옵니다.
// 열쇠가 필요한 곳, 비공개 글, 쪽지, 비밀번호는 부르지 않습니다.
// 주소가 막히거나 인증서가 맞지 않으면 다른 길로 돌아가지 않습니다.

struct PublicFishingNote: Identifiable, Equatable {
    var id: String
    var sourceName: String
    var pageURL: URL
    var writtenAt: Date?
    /// 글에 시·분까지 적혀 있으면 참입니다. 날짜만 있으면 시각을 지어 넣지 않습니다.
    var hasClock: Bool
    var summary: String
}

struct PublicSourceLine: Identifiable, Equatable {
    var name: String
    var detail: String
    /// 그 출처 서버가 응답 번호를 돌려주었으면 참입니다. 인터넷이 끊긴 것과 구분합니다.
    var answered: Bool
    var id: String { name }
}

struct PublicFishingBundle {
    var notes: [PublicFishingNote]
    var lines: [PublicSourceLine]

    var answered: Bool { lines.contains { $0.answered } }
}

enum PublicFishingClient {
    /// 이 날보다 오래된 글은 최신 자료가 아니므로 화면에 올리지 않습니다.
    private static var recentCutoff: Date {
        Calendar(identifier: .gregorian).date(byAdding: .year, value: -3, to: Date())
            ?? Date().addingTimeInterval(-3 * 365 * 24 * 60 * 60)
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 25
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    static func load() async -> PublicFishingBundle {
        async let dinak = loadDinak()
        async let mastodon = loadMastodon()
        async let misskey = loadMisskey()
        async let bluesky = loadBluesky()
        async let news = loadTsurinews()
        let parts = await (dinak, mastodon, misskey, bluesky, news)

        var lines: [PublicSourceLine] = []
        var notes: [PublicFishingNote] = []
        for part in [parts.0, parts.1, parts.2, parts.3, parts.4] {
            lines.append(contentsOf: part.lines)
            notes.append(contentsOf: part.notes)
        }
        return PublicFishingBundle(notes: tidy(notes), lines: lines)
    }

    // MARK: - 디낚 공개 목록

    private static func loadDinak() async -> PublicFishingBundle {
        let boards: [(path: String, name: String)] = [
            ("/proxy/jowhang/낚시인조황", "디낚 낚시인 조황"),
            ("/proxy/jowhang/어종별선상조황", "디낚 선상 조황"),
            ("/proxy/bbs/자료실-낚시터정보", "디낚 낚시터 정보"),
        ]
        var lines: [PublicSourceLine] = []
        var notes: [PublicFishingNote] = []
        for board in boards {
            let result = await loadDinakBoard(path: board.path, name: board.name)
            lines.append(result.line)
            notes.append(contentsOf: result.notes)
        }
        return PublicFishingBundle(notes: notes, lines: lines)
    }

    private static func loadDinakBoard(path: String, name: String) async -> (notes: [PublicFishingNote], line: PublicSourceLine) {
        guard let url = dinakURL(path: path) else {
            return ([], PublicSourceLine(name: name, detail: "공개 주소를 만들지 못했습니다.", answered: false))
        }
        let page = await fetch(url)
        if page.blocked {
            return ([], PublicSourceLine(name: name, detail: "응답이 막혀 있습니다. 우회하지 않습니다.", answered: true))
        }
        guard page.ok, let html = String(data: page.data, encoding: .utf8) else {
            let detail = page.status == 0 ? "연결하지 못했습니다." : "공개 목록을 읽지 못했습니다."
            return ([], PublicSourceLine(name: name, detail: detail, answered: page.status != 0))
        }
        if let final = page.url?.absoluteString, final.contains("login") {
            return ([], PublicSourceLine(name: name, detail: "로그인 화면으로 넘어가 글을 가져오지 않았습니다.", answered: true))
        }
        let parsed = parseDinak(html: html, sourceName: name)
        if parsed.isEmpty {
            return ([], PublicSourceLine(name: name, detail: "최근 3년 안의 공개 글이 없습니다.", answered: true))
        }
        return (parsed, PublicSourceLine(name: name, detail: "공개 글 \(parsed.count)건을 가져왔습니다.", answered: true))
    }

    private static func dinakURL(path: String) -> URL? {
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return looseHTTPS("https://www.dinak.co.kr" + encoded)
    }

    /// 공개 목록에 적힌 제목, 지역, 날짜, 공개 주소만 꺼냅니다.
    private static func parseDinak(html: String, sourceName: String) -> [PublicFishingNote] {
        var notes: [PublicFishingNote] = []
        let rows = html.components(separatedBy: "<tr")
        for row in rows.prefix(40) {
            guard let href = firstMatch("href='(https://www\\.dinak\\.co\\.kr/[^']+)'", in: row),
                  !href.contains("/exec/"),
                  let pageURL = looseHTTPS(unescape(href)) else { continue }
            guard let rawTitle = firstMatch("class='subject'>[\\s\\S]*?<a [^>]*>([\\s\\S]*?)</a>", in: row) else { continue }
            let title = plain(rawTitle)
            guard title.count >= 2 else { continue }
            guard let when = dinakWhen(in: row), when.date >= recentCutoff else { continue }
            let region = plain(firstMatch("class='region'>([\\s\\S]*?)</td>", in: row) ?? "")
            let summary = region.isEmpty ? title : "\(region). \(title)"
            notes.append(PublicFishingNote(
                id: pageURL.absoluteString,
                sourceName: sourceName,
                pageURL: pageURL,
                writtenAt: when.date,
                hasClock: when.hasClock,
                summary: front(summary, limit: 180)
            ))
            if notes.count == 8 { break }
        }
        return notes
    }

    /// 목록의 날짜 칸만 읽습니다. 제목 안의 숫자는 날짜로 쓰지 않습니다.
    /// 네 자리 연도가 없고 `26.10.19`처럼 두 자리만 있으면 2000년을 더합니다. 같은 사이트의 다른 목록은 이 날을 `2026.10.14`로도 적습니다.
    private static func dinakWhen(in row: String) -> (date: Date, hasClock: Bool)? {
        if let stamped = firstMatch("title='([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})'", in: row),
           let parsed = PublicWhen.parse(stamped) {
            return parsed
        }
        let cells = allMatches("class='date'>\\s*([^<]+)", in: row).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var dated: (date: Date, hasClock: Bool)?
        var shortDay: Date?
        var clock: String?
        for cell in cells {
            if let parsed = PublicWhen.parse(cell) {
                if parsed.hasClock { return parsed }
                if dated == nil { dated = parsed }
            }
            if shortDay == nil, let short = PublicWhen.parseShortDay(cell) {
                shortDay = short
            }
            if clock == nil, cell.range(of: "^[0-9]{2}:[0-9]{2}:[0-9]{2}$", options: .regularExpression) != nil {
                clock = cell
            }
        }
        let day = dated?.date ?? shortDay
        if let day, let clock, let combined = PublicWhen.parse("\(PublicWhen.dayStamp(day)) \(clock)") {
            return combined
        }
        if let dated { return dated }
        if let shortDay { return (shortDay, false) }
        return nil
    }

    // MARK: - 마스토돈 공개 태그

    private static func loadMastodon() async -> PublicFishingBundle {
        let tags = ["seafishing", "bassfishing", "바다낚시"]
        var notes: [PublicFishingNote] = []
        var answered = false
        var blocked = false
        var failed = false
        for tag in tags {
            guard let url = URL(string: "https://mastodon.social/api/v1/timelines/tag/\(tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag)?limit=20") else { continue }
            let page = await fetch(url)
            if page.status != 0 { answered = true }
            if page.blocked { blocked = true; continue }
            guard page.ok, let rows = jsonArray(page.data) else { failed = true; continue }
            for row in rows {
                guard let note = mastodonNote(row) else { continue }
                notes.append(note)
            }
        }
        let unique = tidy(notes).prefix(8)
        let detail: String
        if blocked && unique.isEmpty {
            detail = "응답이 막혀 있습니다. 우회하지 않습니다."
        } else if !answered {
            detail = "연결하지 못했습니다."
        } else if unique.isEmpty {
            detail = failed ? "공개 글을 읽지 못했습니다." : "조건에 맞는 공개 글이 없습니다."
        } else {
            detail = "공개 글 \(unique.count)건을 가져왔습니다."
        }
        return PublicFishingBundle(
            notes: Array(unique),
            lines: [PublicSourceLine(name: "마스토돈 공개 글", detail: detail, answered: answered)]
        )
    }

    private static func mastodonNote(_ row: [String: Any]) -> PublicFishingNote? {
        let visibility = row["visibility"] as? String ?? ""
        guard visibility == "public" else { return nil }
        let content = row["content"] as? String ?? ""
        let text = plain(content)
        guard isFieldStory(text), let when = PublicWhen.parse(row["created_at"] as? String ?? "") else { return nil }
        guard let link = row["url"] as? String, let pageURL = URL(string: link), pageURL.scheme == "https" else { return nil }
        let host = pageURL.host ?? "마스토돈"
        return PublicFishingNote(
            id: pageURL.absoluteString,
            sourceName: "마스토돈 · \(host)",
            pageURL: pageURL,
            writtenAt: when.date,
            hasClock: true,
            summary: front(text, limit: 180)
        )
    }

    // MARK: - 미스키 공개 태그

    private static func loadMisskey() async -> PublicFishingBundle {
        let tags = ["海釣り", "釣果", "바다낚시"]
        var notes: [PublicFishingNote] = []
        var answered = false
        var blocked = false
        var failed = false
        for tag in tags {
            guard let url = URL(string: "https://misskey.io/api/notes/search-by-tag") else { continue }
            let body = try? JSONSerialization.data(withJSONObject: ["tag": tag, "limit": 15])
            let page = await fetch(url, method: "POST", body: body, contentType: "application/json")
            if page.status != 0 { answered = true }
            if page.blocked { blocked = true; continue }
            guard page.ok, let rows = jsonArray(page.data) else { failed = true; continue }
            for row in rows {
                guard let note = misskeyNote(row) else { continue }
                notes.append(note)
            }
        }
        let unique = tidy(notes).prefix(8)
        let detail: String
        if blocked && unique.isEmpty {
            detail = "응답이 막혀 있습니다. 우회하지 않습니다."
        } else if !answered {
            detail = "연결하지 못했습니다."
        } else if unique.isEmpty {
            detail = failed ? "공개 글을 읽지 못했습니다." : "조건에 맞는 공개 글이 없습니다."
        } else {
            detail = "공개 글 \(unique.count)건을 가져왔습니다."
        }
        return PublicFishingBundle(
            notes: Array(unique),
            lines: [PublicSourceLine(name: "미스키 공개 글", detail: detail, answered: answered)]
        )
    }

    private static func misskeyNote(_ row: [String: Any]) -> PublicFishingNote? {
        guard (row["visibility"] as? String) == "public" else { return nil }
        let text = plain(row["text"] as? String ?? "")
        guard isFieldStory(text), let when = PublicWhen.parse(row["createdAt"] as? String ?? "") else { return nil }
        guard let id = row["id"] as? String, let pageURL = URL(string: "https://misskey.io/notes/\(id)") else { return nil }
        return PublicFishingNote(
            id: pageURL.absoluteString,
            sourceName: "미스키",
            pageURL: pageURL,
            writtenAt: when.date,
            hasClock: true,
            summary: front(text, limit: 180)
        )
    }

    // MARK: - 블루스카이 공개 검색

    private static func loadBluesky() async -> PublicFishingBundle {
        let name = "블루스카이 공개 검색"
        guard let url = URL(string: "https://public.api.bsky.app/xrpc/app.bsky.feed.searchPosts?q=%EB%B0%94%EB%8B%A4%EB%82%9A%EC%8B%9C%20OR%20%EC%A1%B0%ED%99%A9&limit=20&lang=ko") else {
            return PublicFishingBundle(notes: [], lines: [PublicSourceLine(name: name, detail: "공개 주소를 만들지 못했습니다.", answered: false)])
        }
        let page = await fetch(url)
        if page.blocked {
            return PublicFishingBundle(notes: [], lines: [PublicSourceLine(name: name, detail: "응답이 막혀 있습니다. 우회하지 않습니다.", answered: true)])
        }
        guard page.ok, let object = jsonObject(page.data), let posts = object["posts"] as? [[String: Any]] else {
            let detail = page.status == 0 ? "연결하지 못했습니다." : "공개 검색을 읽지 못했습니다."
            return PublicFishingBundle(notes: [], lines: [PublicSourceLine(name: name, detail: detail, answered: page.status != 0)])
        }
        var notes: [PublicFishingNote] = []
        for post in posts {
            guard let note = blueskyNote(post) else { continue }
            notes.append(note)
            if notes.count == 8 { break }
        }
        let kept = tidy(notes)
        let detail = kept.isEmpty ? "조건에 맞는 공개 글이 없습니다." : "공개 글 \(kept.count)건을 가져왔습니다."
        return PublicFishingBundle(notes: kept, lines: [PublicSourceLine(name: name, detail: detail, answered: true)])
    }

    private static func blueskyNote(_ post: [String: Any]) -> PublicFishingNote? {
        let record = post["record"] as? [String: Any] ?? [:]
        let text = plain(record["text"] as? String ?? "")
        guard isFieldStory(text), let when = PublicWhen.parse(record["createdAt"] as? String ?? "") else { return nil }
        let author = post["author"] as? [String: Any] ?? [:]
        let handle = author["handle"] as? String ?? ""
        guard handle.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression) != nil else { return nil }
        let uri = post["uri"] as? String ?? ""
        guard let rkey = uri.split(separator: "/").last, rkey.isEmpty == false else { return nil }
        guard let pageURL = URL(string: "https://bsky.app/profile/\(handle)/post/\(rkey)") else { return nil }
        return PublicFishingNote(
            id: pageURL.absoluteString,
            sourceName: "블루스카이 · \(handle)",
            pageURL: pageURL,
            writtenAt: when.date,
            hasClock: true,
            summary: front(text, limit: 180)
        )
    }

    // MARK: - 츠리뉴스 공개 소식

    private static func loadTsurinews() async -> PublicFishingBundle {
        let name = "츠리뉴스 공개 소식"
        guard let url = URL(string: "https://www.tsurinews.jp/rss") else {
            return PublicFishingBundle(notes: [], lines: [PublicSourceLine(name: name, detail: "공개 주소를 만들지 못했습니다.", answered: false)])
        }
        let page = await fetch(url)
        if page.blocked {
            return PublicFishingBundle(notes: [], lines: [PublicSourceLine(name: name, detail: "응답이 막혀 있습니다. 우회하지 않습니다.", answered: true)])
        }
        guard page.ok else {
            let detail = page.status == 0 ? "연결하지 못했습니다." : "공개 소식 묶음을 읽지 못했습니다."
            return PublicFishingBundle(notes: [], lines: [PublicSourceLine(name: name, detail: detail, answered: page.status != 0)])
        }
        let reader = RSSItemReader()
        let parser = XMLParser(data: page.data)
        parser.delegate = reader
        guard parser.parse() else {
            return PublicFishingBundle(notes: [], lines: [PublicSourceLine(name: name, detail: "공개 소식 묶음을 읽지 못했습니다.", answered: true)])
        }
        var notes: [PublicFishingNote] = []
        for item in reader.items {
            guard let pageURL = URL(string: item.link), pageURL.scheme == "https",
                  let host = pageURL.host, host == "tsurinews.jp" || host == "www.tsurinews.jp" else { continue }
            let title = plain(item.title)
            guard title.count >= 2, let when = PublicWhen.parse(item.date), when.date >= recentCutoff else { continue }
            let body = plain(item.summary)
            let summary = body.count > title.count + 40 ? front(body, limit: 180) : title
            notes.append(PublicFishingNote(
                id: pageURL.absoluteString,
                sourceName: name,
                pageURL: pageURL,
                writtenAt: when.date,
                hasClock: when.hasClock,
                summary: summary
            ))
            if notes.count == 6 { break }
        }
        let detail = notes.isEmpty ? "최근 3년 안의 공개 글이 없습니다." : "공개 글 \(notes.count)건을 가져왔습니다."
        return PublicFishingBundle(notes: notes, lines: [PublicSourceLine(name: name, detail: detail, answered: true)])
    }

    // MARK: - 고르기

    /// 현장 이야기인지 글자만 보고 가립니다. 글을 새로 만들지 않습니다.
    private static func isFieldStory(_ text: String) -> Bool {
        guard text.count >= 8 else { return false }
        let lowered = text.lowercased()
        if lowered.contains("mmsi") || lowered.contains("vesselalert") || lowered.contains("global audition") || text.contains("오디션") {
            return false
        }
        let words = ["조황", "포인트", "물때", "입질", "방파제", "갯바위", "찌낚시", "원투", "에깅", "루어", "감성돔", "우럭", "광어", "농어", "조과", "씨알", "바다낚시", "민물낚시", "해루질", "갯벌", "밑밥", "만조", "간조", "들물", "날물", "문어", "갈치", "fishing", "angling", "lure", "bass", "tide", "釣", "釣果", "堤防"]
        return words.contains { text.range(of: $0, options: .caseInsensitive) != nil }
    }

    private static func tidy(_ notes: [PublicFishingNote]) -> [PublicFishingNote] {
        var seen: Set<String> = []
        var kept: [PublicFishingNote] = []
        let ordered = notes.sorted { left, right in
            (left.writtenAt ?? .distantPast) > (right.writtenAt ?? .distantPast)
        }
        for note in ordered {
            guard let writtenAt = note.writtenAt, writtenAt >= recentCutoff else { continue }
            guard seen.insert(note.id).inserted else { continue }
            guard note.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { continue }
            kept.append(note)
            if kept.count == 24 { break }
        }
        return kept
    }

    // MARK: - 받기

    private struct Page {
        var status: Int
        var data: Data
        var url: URL?
        var blocked: Bool { [401, 403, 429, 451].contains(status) }
        var ok: Bool { (200..<300).contains(status) && url?.scheme == "https" }
    }

    private static func fetch(_ url: URL, method: String = "GET", body: Data? = nil, contentType: String? = nil) async -> Page {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("BaroNaksi/0.1 (public fishing notes)", forHTTPHeaderField: "User-Agent")
        request.setValue("ko", forHTTPHeaderField: "Accept-Language")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        request.httpBody = body
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return Page(status: 0, data: Data(), url: nil)
            }
            return Page(status: http.statusCode, data: data, url: http.url)
        } catch {
            return Page(status: 0, data: Data(), url: nil)
        }
    }

    private static func jsonArray(_ data: Data) -> [[String: Any]]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        allMatches(pattern, in: text).first
    }

    private static func allMatches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let span = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[span])
        }
    }

    private static func plain(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</p>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        text = unescape(text)
        let parts = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    private static func unescape(_ raw: String) -> String {
        var text = raw.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
        while let start = text.range(of: "&#") {
            let tail = text[start.upperBound...]
            let hex = tail.hasPrefix("x") || tail.hasPrefix("X")
            let digits = tail.dropFirst(hex ? 1 : 0)
            guard let end = digits.firstIndex(of: ";") else { break }
            let token = digits[..<end]
            let value = hex ? Int(token, radix: 16) : Int(token, radix: 10)
            if let value, let scalar = UnicodeScalar(value) {
                text.replaceSubrange(start.lowerBound...end, with: String(Character(scalar)))
            } else {
                text.replaceSubrange(start.lowerBound...end, with: "")
            }
        }
        return text
    }

    private static func front(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let end = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<end]) + "…"
    }

    /// 한글 주소는 퍼센트 기호로 바꾸고, 이미 있는 https 구조는 그대로 둡니다.
    private static func looseHTTPS(_ raw: String) -> URL? {
        guard raw.hasPrefix("https://") else { return nil }
        var out = ""
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=%")
        for scalar in raw.unicodeScalars {
            if allowed.contains(scalar) {
                out.unicodeScalars.append(scalar)
            } else if let data = String(scalar).data(using: .utf8) {
                for byte in data {
                    out += String(format: "%%%02X", byte)
                }
            }
        }
        guard let url = URL(string: out), url.host == "www.dinak.co.kr" else { return nil }
        return url
    }
}

enum PublicWhen {
    static func parse(_ raw: String) -> (date: Date, hasClock: Bool)? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return nil }
        text = text.replacingOccurrences(of: "\\([월화수목금토일]\\)", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) { return (date, true) }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return (date, true) }

        let posix = Locale(identifier: "en_US_POSIX")
        let seoul = TimeZone(identifier: "Asia/Seoul")
        if text.contains(":") {
            let clock = DateFormatter()
            clock.locale = posix
            clock.timeZone = seoul
            for format in ["yyyy.MM.dd HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "EEE, dd MMM yyyy HH:mm:ss Z"] {
                clock.dateFormat = format
                clock.timeZone = format.contains("Z") ? TimeZone(secondsFromGMT: 0) : seoul
                if let date = clock.date(from: text) { return (date, true) }
            }
        }
        let day = DateFormatter()
        day.locale = posix
        day.timeZone = seoul
        let dayText = String(text.prefix(10)).replacingOccurrences(of: "-", with: ".")
        day.dateFormat = "yyyy.MM.dd"
        if dayText.count == 10, let date = day.date(from: dayText) {
            return (date, false)
        }
        return nil
    }

    /// `26.10.19`를 2026-10-19로 읽습니다. 월·일이 달력 범위를 벗어나면 버립니다.
    static func parseShortDay(_ raw: String) -> Date? {
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard parts.count == 3,
              parts[0].count == 2, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (0...69).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? TimeZone(secondsFromGMT: 9 * 60 * 60) ?? .current
        calendar.isLenient = false
        var pieces = DateComponents()
        pieces.calendar = calendar
        pieces.timeZone = calendar.timeZone
        pieces.year = 2000 + year
        pieces.month = month
        pieces.day = day
        return pieces.date
    }

    static func dayStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date)
    }
}

final class RSSItemReader: NSObject, XMLParserDelegate {
    struct Item {
        var title = ""
        var link = ""
        var date = ""
        var summary = ""
    }

    var items: [Item] = []
    private var current = Item()
    private var text = ""
    private var inItem = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        if elementName == "item" {
            inItem = true
            current = Item()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) {
            text += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard inItem else { return }
        switch elementName {
        case "title": current.title += text
        case "link": current.link += text
        case "pubDate": current.date += text
        case "description": current.summary += text
        case "item":
            items.append(current)
            inItem = false
        default:
            break
        }
        text = ""
    }
}
