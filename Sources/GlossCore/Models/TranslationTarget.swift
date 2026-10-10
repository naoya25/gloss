import Foundation

public enum TranslationTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case japanese
    case english

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .auto: "Auto"
        case .japanese: "To Japanese"
        case .english: "To English"
        }
    }
}
