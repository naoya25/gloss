import Foundation

public enum TranslationTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case japanese
    case english

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .auto: "自動"
        case .japanese: "日本語へ"
        case .english: "英語へ"
        }
    }
}
