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
            "\(engine.displayName) の API キーが Keychain にありません(\(engine.keychainService))"
        case .missingUserID:
            "JAPAN AI Gateway のユーザーID が未設定です。設定(⌘,)で会社のメールアドレスを入れてください"
        case .http(let status, let engine):
            switch status {
            case 401, 403: "\(engine.displayName) の API キーが無効です"
            case 429: "\(engine.displayName) がレート制限中です。少し待って再試行してください"
            case 500...599: "\(engine.displayName) 側で障害が起きています(HTTP \(status))"
            default: "\(engine.displayName) API エラー(HTTP \(status))"
            }
        }
    }
}
