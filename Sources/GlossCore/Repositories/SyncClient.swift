import Foundation

public enum SyncError: LocalizedError, Equatable {
    case badURL
    case unauthorized
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .badURL: "The sync URL is invalid"
        case .unauthorized: "The sync token is wrong"
        case .http(let status): "Couldn't sync (HTTP \(status))"
        }
    }
}

// Cloudflare Workers の単語帳 API(cloud/src/index.js)と話す
public struct SyncClient: Sendable {
    public static let keychainService = "gloss-sync"
    public static let maxRowsPerPush = 100

    let endpoint: URL
    let token: String

    public init(baseURL: String, token: String) throws {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = URL(string: trimmed), base.scheme == "https", base.host != nil else { throw SyncError.badURL }
        endpoint = base.appendingPathComponent("api/words")
        self.token = token
    }

    public func pull(since cursor: Int) async throws -> SyncPage {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "since", value: String(cursor))]
        let data = try await send(URLRequest(url: components.url!))
        return try Self.decoder.decode(SyncPage.self, from: data)
    }

    public func push(_ rows: [SyncRow]) async throws {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.encoder.encode(["words": rows])
        _ = try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw SyncError.unauthorized }
        guard (200..<300).contains(status) else { throw SyncError.http(status) }
        return data
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
