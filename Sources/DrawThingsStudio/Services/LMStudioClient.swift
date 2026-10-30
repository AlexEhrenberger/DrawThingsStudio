import Foundation

/// Nachricht im OpenAI-kompatiblen Chat-Format von LM Studio.
struct ChatMessage {
    enum Part {
        case text(String)
        case image(dataURL: String)
    }

    let role: String
    let parts: [Part]

    static func system(_ text: String) -> ChatMessage { ChatMessage(role: "system", parts: [.text(text)]) }
    static func user(_ text: String, images: [String] = []) -> ChatMessage {
        ChatMessage(role: "user", parts: [.text(text)] + images.map { .image(dataURL: $0) })
    }
    static func assistant(_ text: String) -> ChatMessage { ChatMessage(role: "assistant", parts: [.text(text)]) }

    var json: [String: Any] {
        if parts.count == 1, case .text(let text) = parts[0] {
            return ["role": role, "content": text]
        }
        return [
            "role": role,
            "content": parts.map { part -> [String: Any] in
                switch part {
                case .text(let text): ["type": "text", "text": text]
                case .image(let url): ["type": "image_url", "image_url": ["url": url]]
                }
            },
        ]
    }
}

enum LMStatus: Equatable {
    case unknown
    case offline
    case modelMissing
    case notLoaded
    case loading
    case ready

    var title: String {
        switch self {
        case .unknown: "Verbinde …"
        case .offline: "LM Studio nicht erreichbar"
        case .modelMissing: "Modell nicht gefunden"
        case .notLoaded: "Bereit (lädt bei Bedarf)"
        case .loading: "Modell wird geladen …"
        case .ready: "Bereit"
        }
    }
}

extension URLSession {
    /// Für LM Studio und Draw Things: nichts auf die Platte – kein Zwischenspeicher, keine Cookies.
    /// Prompts, Bilder und Gemmas Antworten gehören in die Bibliothek, nicht nach `~/Library/Caches`.
    static let local: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }()

    /// Bis 12.10.2026 lief alles über `URLSession.shared` – das legte Antworten (auch von Gemma) in
    /// `~/Library/Caches/<Bundle-ID>` und Cookies in `~/Library/HTTPStorages/<Bundle-ID>` ab. Beim Start wegräumen.
    static func removeLegacyDiskCaches() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            let library = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            let cache = library.appending(path: "Caches/\(bundleID)", directoryHint: .isDirectory)
            for name in ["Cache.db", "Cache.db-shm", "Cache.db-wal", "fsCachedData", ".DS_Store"] {
                try? fm.removeItem(at: cache.appending(path: name))
            }
            if (try? fm.contentsOfDirectory(atPath: cache.path))?.isEmpty == true { try? fm.removeItem(at: cache) }
            try? fm.removeItem(at: library.appending(path: "HTTPStorages/\(bundleID)", directoryHint: .isDirectory))
            try? fm.removeItem(at: library.appending(path: "HTTPStorages/\(bundleID).binarycookies"))
        }
    }
}

struct ServiceError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

struct LMStudioClient {
    var baseURL: URL
    var model: String

    init(baseURL: String, model: String) {
        self.baseURL = URL(string: baseURL.trimmingCharacters(in: .whitespaces)) ?? URL(string: "http://127.0.0.1:1234")!
        self.model = model
    }

    // MARK: Status

    func status() async -> LMStatus {
        var request = URLRequest(url: baseURL.appending(path: "api/v1/models"))
        request.timeoutInterval = 3
        do {
            let (data, response) = try await URLSession.local.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let models = object["models"] as? [[String: Any]] else {
                return await legacyStatus()
            }
            guard let entry = models.first(where: { ($0["key"] as? String) == model }) else { return .modelMissing }
            let loaded = (entry["loaded_instances"] as? [Any])?.isEmpty == false
            return loaded ? .ready : .notLoaded
        } catch {
            return .offline
        }
    }

    /// Ältere LM-Studio-Versionen kennen nur /v1/models.
    private func legacyStatus() async -> LMStatus {
        var request = URLRequest(url: baseURL.appending(path: "v1/models"))
        request.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.local.data(for: request),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = object["data"] as? [[String: Any]] else { return .offline }
        return list.contains { ($0["id"] as? String) == model } ? .ready : .modelMissing
    }

    func availableModels() async -> [String] {
        var request = URLRequest(url: baseURL.appending(path: "v1/models"))
        request.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.local.data(for: request),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = object["data"] as? [[String: Any]] else { return [] }
        return list.compactMap { $0["id"] as? String }.filter { !$0.contains("embed") }
    }

    func load() async throws {
        var request = URLRequest(url: baseURL.appending(path: "api/v1/models/load"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model])
        request.timeoutInterval = 300
        let (data, response) = try await URLSession.local.data(for: request)
        try Self.check(response, data)
    }

    // MARK: Chat

    func complete(_ messages: [ChatMessage], temperature: Double = 0.3, maxTokens: Int = 800, schema: [String: Any]? = nil) async throws -> String {
        var body = self.body(messages, temperature: temperature, maxTokens: maxTokens)
        body["stream"] = false
        if let schema {
            body["response_format"] = ["type": "json_schema", "json_schema": ["name": "result", "strict": true, "schema": schema]]
        }
        var request = URLRequest(url: baseURL.appending(path: "v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 300
        let (data, response) = try await URLSession.local.data(for: request)
        try Self.check(response, data)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ServiceError("Unerwartete Antwort von LM Studio.")
        }
        return content
    }

    /// Antwort Stück für Stück (Server-Sent Events), damit der Text live erscheint.
    func stream(_ messages: [ChatMessage], temperature: Double = 0.3, maxTokens: Int = 800) -> AsyncThrowingStream<String, Error> {
        var body = self.body(messages, temperature: temperature, maxTokens: maxTokens)
        body["stream"] = true
        let url = baseURL.appending(path: "v1/chat/completions")
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    request.timeoutInterval = 300
                    let (bytes, response) = try await URLSession.local.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        try Self.check(response, data)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = object["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let content = delta["content"] as? String else { continue }
                        continuation.yield(content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func body(_ messages: [ChatMessage], temperature: Double, maxTokens: Int) -> [String: Any] {
        [
            "model": model,
            "messages": messages.map(\.json),
            "temperature": temperature,
            "max_tokens": maxTokens,
        ]
    }

    static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = (object?["error"] as? [String: Any])?["message"] as? String
            ?? object?["error"] as? String
            ?? String(data: data, encoding: .utf8)
            ?? "HTTP \(http.statusCode)"
        throw ServiceError("LM Studio: \(message)")
    }

    /// Entfernt Einleitungen, Markdown und Anführungszeichen um den ganzen Text.
    static func clean(_ raw: String) -> String {
        var text = raw
        if let range = text.range(of: "</think>") { text = String(text[range.upperBound...]) }
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: "```", with: "")
        var lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        while let first = lines.first, first.isEmpty || first.hasSuffix(":") && first.count < 60 {
            lines.removeFirst()
        }
        text = lines.filter { !$0.isEmpty }.joined(separator: " ")
        for prefix in ["Prompt:", "Optimized prompt:", "Rewritten prompt:", "Final prompt:", "Edit instruction:"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > 2, let first = text.first, let last = text.last,
           (first == "\"" && last == "\"") || (first == "“" && last == "”") {
            let inner = text.dropFirst().dropLast()
            if !inner.contains("\"") { text = String(inner) }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
