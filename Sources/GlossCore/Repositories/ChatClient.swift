import Foundation

public enum SSEEvent: Equatable {
    case delta(String)
    case done
    case ignore

    public static func parse(line: String) -> SSEEvent {
        guard line.hasPrefix("data:") else { return .ignore }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard
            let data = payload.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let delta = choices.first?["delta"] as? [String: Any],
            let content = delta["content"] as? String,
            !content.isEmpty
        else { return .ignore }
        return .delta(content)
    }
}

public struct ChatClient: Sendable {
    public var engine: Engine
    public var model: String
    public var userID: String

    public init(engine: Engine, model: String, userID: String) {
        self.engine = engine
        self.model = model
        self.userID = userID
    }

    public func stream(_ messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(messages)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw GlossError.http(status: http.statusCode, engine: engine)
                    }
                    for try await line in bytes.lines {
                        switch SSEEvent.parse(line: line) {
                        case .delta(let text): continuation.yield(text)
                        case .done:
                            continuation.finish()
                            return
                        case .ignore: continue
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func makeRequest(_ messages: [ChatMessage]) throws -> URLRequest {
        guard let key = Keychain.apiKey(service: engine.keychainService) else {
            throw GlossError.missingAPIKey(engine)
        }
        var request = URLRequest(url: try engine.chatURL(userID: userID))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: Self.body(model: model, messages: messages))
        return request
    }

    static func body(model: String, messages: [ChatMessage]) -> [String: Any] {
        [
            "model": model,
            "stream": true,
            "messages": messages.map(encode),
        ]
    }

    private static func encode(_ message: ChatMessage) -> [String: Any] {
        guard !message.images.isEmpty else {
            return ["role": message.role.rawValue, "content": message.text]
        }
        var parts: [[String: Any]] = [["type": "text", "text": message.text]]
        for image in message.images {
            parts.append([
                "type": "image_url",
                "image_url": ["url": "data:image/jpeg;base64,\(image.base64EncodedString())"],
            ])
        }
        return ["role": message.role.rawValue, "content": parts]
    }
}
