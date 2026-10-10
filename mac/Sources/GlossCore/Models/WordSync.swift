import Foundation

// Cloudflare に置く単語1件。時刻はミリ秒で持つ。Gloss の JSON は秒までしか残さないため
public struct SyncRow: Codable, Equatable, Sendable {
    public var id: String
    public var updatedAt: Int64
    public var deleted: Bool
    public var data: WordEntry?

    public init(id: String, updatedAt: Int64, deleted: Bool, data: WordEntry?) {
        self.id = id
        self.updatedAt = updatedAt
        self.deleted = deleted
        self.data = data
    }
}

public struct SyncPage: Codable, Sendable {
    public var words: [SyncRow]
    public var cursor: Int
    public var hasMore: Bool
}

// まだ Cloudflare に送れていない変更と、どこまで取ってきたかを sync.json に残す
public struct SyncLedger: Codable, Equatable, Sendable {
    public var cursor = 0
    public var pending: [String: Int64] = [:]

    public init() {}

    // 初めて同期するときは、手元の単語を全部送る。最後に触った時刻を付けて、
    // 別の Mac がもっと新しく書いた単語を古い内容で上書きしないようにする
    public static func initial(for words: [WordEntry]) -> SyncLedger {
        var ledger = SyncLedger()
        for word in words {
            ledger.pending[word.id.uuidString] = WordSync.millis(word.updatedAt ?? word.lastReviewed ?? word.date)
        }
        return ledger
    }

    public mutating func markChanged(_ id: UUID, at date: Date) {
        pending[id.uuidString] = WordSync.millis(date)
    }

    public func rows(from words: [WordEntry]) -> [SyncRow] {
        let byID = Dictionary(words.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        return pending.sorted { $0.key < $1.key }.map { id, time in
            let word = byID[id]
            return SyncRow(id: id, updatedAt: time, deleted: word == nil, data: word)
        }
    }

    // 送っている間にまた変わった単語は、次にもう一度送る
    public mutating func didPush(_ rows: [SyncRow]) {
        for row in rows where pending[row.id] == row.updatedAt {
            pending[row.id] = nil
        }
    }
}

public enum WordSync {
    public static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    public static func date(_ millis: Int64) -> Date {
        Date(timeIntervalSince1970: Double(millis) / 1000)
    }

    // 単語ごとに、新しいほうを残す。まだ送っていない手元の変更が新しければ、それを残す
    public static func merge(_ local: [WordEntry], with rows: [SyncRow], ledger: SyncLedger) -> [WordEntry] {
        var words = local
        for row in rows {
            if let mine = ledger.pending[row.id], mine >= row.updatedAt { continue }
            let index = words.firstIndex { $0.id.uuidString == row.id }
            if let index, millis(words[index].updatedAt ?? .distantPast) >= row.updatedAt { continue }
            guard !row.deleted, var entry = row.data else {
                if let index { words.remove(at: index) }
                continue
            }
            entry.updatedAt = date(row.updatedAt)
            if let index {
                words[index] = entry
            } else {
                words.insert(entry, at: 0)
            }
        }
        return words
    }
}
