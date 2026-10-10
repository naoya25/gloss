import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var engine: Engine = .jai
    public var model: String = Engine.jai.defaultModel
    public var jaiUserID: String = ""
    public var target: TranslationTarget = .auto
    public var cardFace: CardFace = .english
    public var wordSort: WordSort = .stale
    public var syncURL: String = ""

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
        syncURL = try container.decodeIfPresent(String.self, forKey: .syncURL) ?? syncURL
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
