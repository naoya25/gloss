import Foundation

public struct ChatMessage: Sendable, Equatable, Identifiable {
    public enum Role: String, Sendable {
        case system, user, assistant
    }

    public let id = UUID()
    public var role: Role
    public var text: String
    public var images: [Data]

    public init(_ role: Role, _ text: String, images: [Data] = []) {
        self.role = role
        self.text = text
        self.images = images
    }

    public static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id && lhs.text == rhs.text
    }
}
