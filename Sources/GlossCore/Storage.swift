import Foundation

public struct HistoryItem: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var source: String
    public var translation: String
    public var imageFile: String?

    public init(source: String, translation: String, imageFile: String? = nil) {
        self.source = source
        self.translation = translation
        self.imageFile = imageFile
    }

    public var title: String {
        let line = source.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return line.isEmpty ? (imageFile == nil ? "(空)" : "画像") : line
    }
}

public struct WordEntry: Codable, Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var date = Date()
    public var term: String
    public var note: String
    public var context: String
    // ここから下はフラッシュカード用。古い words.json には無いので Optional にして、無くても読めるようにする
    public var english: String?
    public var japanese: String?
    public var example: String?
    public var exampleTranslation: String?
    public var flips: Int?
    public var lastReviewed: Date?
    public var mastery: Mastery?

    public init(term: String, note: String, context: String) {
        self.term = term
        self.note = note
        self.context = context
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var engine: Engine = .jai
    public var model: String = Engine.jai.defaultModel
    public var jaiUserID: String = ""
    public var target: TranslationTarget = .auto
    public var cardFace: CardFace = .english
    public var wordSort: WordSort = .stale

    public init() {}

    // 項目を足しても古い settings.json を読めるように、無いキーは既定値のままにする
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        engine = try container.decodeIfPresent(Engine.self, forKey: .engine) ?? engine
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? model
        jaiUserID = try container.decodeIfPresent(String.self, forKey: .jaiUserID) ?? jaiUserID
        target = try container.decodeIfPresent(TranslationTarget.self, forKey: .target) ?? target
        cardFace = try container.decodeIfPresent(CardFace.self, forKey: .cardFace) ?? cardFace
        wordSort = try container.decodeIfPresent(WordSort.self, forKey: .wordSort) ?? wordSort
    }

    // TraPoP の設定(com.naoya-otsuka.trapop/config.json)を初回だけ引き継ぐ
    public static func importingTraPoP(from url: URL) -> AppSettings {
        var settings = AppSettings()
        guard
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return settings }
        if let choice = json["engine_choice"] as? String, let engine = Engine(rawValue: choice) {
            settings.engine = engine
            settings.model = engine.defaultModel
        }
        if let model = json["model_override"] as? String, !model.isEmpty {
            settings.model = model
        }
        if let userID = json["jai_user_id"] as? String {
            settings.jaiUserID = userID
        }
        return settings
    }
}

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
    public static let images = support.appendingPathComponent("images", isDirectory: true)
    public static let traPoPConfig = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.naoya-otsuka.trapop/config.json")
}
