import Foundation

public struct JSONFile<Value: Codable> {
    public let url: URL

    public init(_ url: URL) {
        self.url = url
    }

    public func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Value.self, from: data)
    }

    public func save(_ value: Value) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

public enum AppPaths {
    public static let support: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Gloss", isDirectory: true)
    public static let settings = support.appendingPathComponent("settings.json")
    public static let history = support.appendingPathComponent("history.json")
    public static let words = support.appendingPathComponent("words.json")
    public static let sync = support.appendingPathComponent("sync.json")
    public static let activity = support.appendingPathComponent("activity.json")
    public static let activitySync = support.appendingPathComponent("activity-sync.json")
    public static let images = support.appendingPathComponent("images", isDirectory: true)
    public static let traPoPConfig = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.naoya-otsuka.trapop/config.json")
}
