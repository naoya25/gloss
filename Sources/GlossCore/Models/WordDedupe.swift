import Foundation

extension WordEntry {
    // 同じ単語かどうかを決める鍵。大文字小文字・前後の空白と記号・空白の数の違いは同じとみなす
    public static func key(for term: String) -> String {
        term.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.whitespaces).subtracting(CharacterSet(charactersIn: "'")))
    }

    public var key: String { Self.key(for: term) }
}

public enum WordDedupe {
    public struct Result: Equatable, Sendable {
        public var words: [WordEntry]
        // まとめた先の単語と、消した単語。同期でどちらも送る
        public var changedIDs: [UUID]
        public var removedIDs: [UUID]
    }

    // 同じ単語が2つ以上あれば、いちばん古く追加したものに学習記録を寄せて1つにする
    public static func merge(_ words: [WordEntry]) -> Result {
        var firstIndex: [String: Int] = [:]
        var result: [WordEntry] = []
        var changed: [UUID] = []
        var removed: [UUID] = []
        for word in words {
            guard let index = firstIndex[word.key] else {
                firstIndex[word.key] = result.count
                result.append(word)
                continue
            }
            let (kept, dropped) = result[index].date <= word.date ? (result[index], word) : (word, result[index])
            result[index] = combine(kept, with: dropped)
            changed.append(kept.id)
            removed.append(dropped.id)
        }
        let removedSet = Set(removed)
        return Result(words: result, changedIDs: Array(Set(changed).subtracting(removedSet)), removedIDs: removed)
    }

    static func combine(_ kept: WordEntry, with other: WordEntry) -> WordEntry {
        var word = kept
        let flips = (kept.flips ?? 0) + (other.flips ?? 0)
        word.flips = flips == 0 ? kept.flips : flips
        word.lastReviewed = [kept.lastReviewed, other.lastReviewed].compactMap { $0 }.max()
        // 覚えた度合いは、最後にめくったほうに合わせる
        if (other.lastReviewed ?? .distantPast) > (kept.lastReviewed ?? .distantPast), let mastery = other.mastery {
            word.mastery = mastery
        } else if word.mastery == nil {
            word.mastery = other.mastery
        }
        if word.note.isEmpty { word.note = other.note }
        if word.context.isEmpty { word.context = other.context }
        if !word.isCardComplete && other.isCardComplete {
            word.english = other.english
            word.japanese = other.japanese
            word.example = other.example
            word.exampleTranslation = other.exampleTranslation
            word.cardError = nil
        }
        return word
    }
}
