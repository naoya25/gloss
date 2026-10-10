import Foundation

public enum Engine: String, Codable, CaseIterable, Identifiable, Sendable {
    case jai
    case openai
    case gemini

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .jai: "JAPAN AI Gateway"
        case .openai: "OpenAI"
        case .gemini: "Gemini"
        }
    }

    // TraPoP と同じ Keychain の項目を読むので、キーを入れ直さずに済む
    public var keychainService: String { "trapop-\(rawValue)" }

    public var defaultModel: String {
        switch self {
        case .jai: "gemini-3.1-flash-lite"
        case .openai: "gpt-4.1-mini"
        case .gemini: "gemini-flash-latest"
        }
    }

    public func chatURL(userID: String) throws -> URL {
        switch self {
        case .openai:
            return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .gemini:
            return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!
        case .jai:
            let trimmed = userID.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { throw GlossError.missingUserID }
            var components = URLComponents(string: "https://api.japan-ai.co.jp/v1/chat/completions")!
            components.queryItems = [URLQueryItem(name: "userId", value: trimmed)]
            return components.url!
        }
    }
}

public enum GlossError: LocalizedError, Equatable {
    case missingAPIKey(Engine)
    case missingUserID
    case http(status: Int, engine: Engine)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let engine):
            "No \(engine.displayName) API key in Keychain (\(engine.keychainService))"
        case .missingUserID:
            "JAPAN AI Gateway user ID is not set. Enter your work email in Settings (⌘,)."
        case .http(let status, let engine):
            switch status {
            case 401, 403: "The \(engine.displayName) API key is invalid"
            case 429: "\(engine.displayName) is rate limiting requests. Wait a moment and try again."
            case 500...599: "\(engine.displayName) is having problems (HTTP \(status))"
            default: "\(engine.displayName) API error (HTTP \(status))"
            }
        }
    }
}
