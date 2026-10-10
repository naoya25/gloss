import Foundation

// Cloudflare に置く学習の記録1件
public struct ActivityRow: Codable, Equatable, Sendable {
    public var id: String
    public var date: Int64
    public var kind: String
    public var wordID: String?
    public var data: ActivityEvent

    public init(_ event: ActivityEvent) {
        id = event.id.uuidString
        date = WordSync.millis(event.date)
        kind = event.kind.rawValue
        wordID = event.wordID?.uuidString
        data = event
    }
}

public struct ActivityPage: Codable, Sendable {
    public var events: [ActivityRow]
    public var cursor: Int
    public var hasMore: Bool
}

// まだ送れていない記録と、どこまで取ってきたかを activity-sync.json に残す
public struct ActivityLedger: Codable, Equatable, Sendable {
    public var cursor = 0
    public var pending: Set<String> = []

    public init() {}

    // 初めて同期するときは、手元の記録を全部送る
    public static func initial(for events: [ActivityEvent]) -> ActivityLedger {
        var ledger = ActivityLedger()
        ledger.pending = Set(events.map(\.id.uuidString))
        return ledger
    }

    public func rows(from events: [ActivityEvent]) -> [ActivityRow] {
        events.filter { pending.contains($0.id.uuidString) }.map(ActivityRow.init)
    }

    public mutating func didPush(_ rows: [ActivityRow]) {
        pending.subtract(rows.map(\.id))
    }
}

public enum ActivitySync {
    // 記録は書き換えないので、まだ持っていないものを足すだけでいい
    public static func merge(_ local: [ActivityEvent], with rows: [ActivityRow]) -> [ActivityEvent] {
        let known = Set(local.map(\.id))
        let added = rows.map(\.data).filter { !known.contains($0.id) }
        guard !added.isEmpty else { return local }
        return (local + added).sorted { $0.date < $1.date }
    }
}
