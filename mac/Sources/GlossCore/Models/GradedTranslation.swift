import Foundation

// 訳の中にどれくらい英語を残すか。50% までは日本語の文に英語の語句を残し、90% は英語の原文に難しい語句だけ日本語を添える。
// 日本語の文に英語を 90% 混ぜると、語順が日本語のままの読みにくい文になるため
public enum EnglishLevel: Int, CaseIterable, Identifiable, Codable, Sendable {
    case japanese = 0
    case ten = 10
    case thirty = 30
    case fifty = 50
    case ninety = 90

    public var id: Int { rawValue }

    public var label: String {
        self == .japanese ? "日本語" : "\(rawValue)%"
    }
}

// 訳の中の英語の語句1つ。difficulty は AI が付けたやさしさ(1 やさしい〜5 難しい)。Book で ✓ の語は 0
public struct GlossedPhrase: Equatable, Sendable {
    public var english: String
    public var japanese: String
    public var difficulty: Int
    public var isLearned: Bool
}

// AI に1回だけ訳してもらい、語句ごとに英語と日本語の両方を持っておく。段階を変えても AI を呼び直さない
public struct GradedTranslation: Equatable, Sendable {
    public enum Segment: Equatable, Sendable {
        case plain(String)
        case phrase(GlossedPhrase)
    }

    public var segments: [Segment]
    public var source: String

    // AI は語句を「⟦hotfix | 緊急修正 | 4⟧」の形で書く。受信途中の書きかけの「⟦…」は出さない。
    // 英文に無い語句は、AI が作った語なので日本語のままにする
    public static func parse(_ raw: String, knownTerms: [String], source: String) -> GradedTranslation {
        let known = Set(knownTerms.map { $0.lowercased() })
        var segments: [Segment] = []
        var rest = Substring(raw)
        while let start = rest.firstIndex(of: MixedTranslation.open) {
            if start > rest.startIndex { segments.append(.plain(String(rest[..<start]))) }
            guard let end = rest[start...].firstIndex(of: MixedTranslation.close) else {
                rest = ""
                break
            }
            let parts = rest[rest.index(after: start)..<end].split(separator: "|", maxSplits: 2).map { $0.trimmingCharacters(in: .whitespaces) }
            let english = parts.first ?? ""
            let japanese = parts.count > 1 ? parts[1] : english
            let isLearned = known.contains(english.lowercased())
            if english.isEmpty || !Self.appears(english, in: source) {
                segments.append(.plain(japanese))
            } else {
                let difficulty = isLearned ? 0 : (parts.count > 2 ? Int(parts[2].prefix { $0.isNumber }) ?? 3 : 3)
                segments.append(.phrase(GlossedPhrase(english: english, japanese: japanese, difficulty: difficulty, isLearned: isLearned)))
            }
            rest = rest[rest.index(after: end)...]
        }
        if !rest.isEmpty { segments.append(.plain(String(rest))) }
        return GradedTranslation(segments: segments, source: source)
    }

    // 長い英文は、空行で区切った段落を limit 文字ほどずつにまとめて、別々に訳してもらう。
    // 一度に長い文を頼むと、AI が語句の印を付け忘れて、英語に戻せる語句がほとんど無くなるため
    public static func parts(of source: String, limit: Int = 1_200) -> [String] {
        let paragraphs = source.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var parts: [String] = []
        var current = ""
        for paragraph in paragraphs {
            if !current.isEmpty, current.count + paragraph.count > limit {
                parts.append(current)
                current = ""
            }
            current += current.isEmpty ? paragraph : "\n\n" + paragraph
        }
        if !current.isEmpty { parts.append(current) }
        return parts.isEmpty ? [source] : parts
    }

    // 分けて訳したものを、空行でつないで1つに戻す
    public static func joined(_ parts: [GradedTranslation], source: String) -> GradedTranslation {
        var segments: [Segment] = []
        for part in parts {
            if !segments.isEmpty { segments.append(.plain("\n\n")) }
            segments += part.segments
        }
        return GradedTranslation(segments: segments, source: source)
    }

    // 動詞は原形で書かせるので、英文の中では活用した形(pushed, migrating)で出てくることがある。その形も探す
    static func appears(_ english: String, in source: String) -> Bool {
        if MixedTranslation.contains(english, in: source) { return true }
        var words = english.split(separator: " ").map(String.init)
        guard let first = words.first else { return false }
        let stem = first.hasSuffix("e") ? String(first.dropLast()) : first
        for form in [first + "s", first + "es", first + "d", first + "ed", stem + "ing", first + first.suffix(1) + "ed", first + first.suffix(1) + "ing"] {
            words[0] = form
            if MixedTranslation.contains(words.joined(separator: " "), in: source) { return true }
        }
        return false
    }

    public var phrases: [GlossedPhrase] {
        segments.compactMap { if case let .phrase(phrase) = $0 { phrase } else { nil } }
    }

    public var japanese: String {
        segments.map { segment in
            switch segment {
            case let .plain(text): text
            case let .phrase(phrase): phrase.japanese
            }
        }.joined()
    }

    // その段階で読む訳。日本語の段階は全文の和訳、90% は原文、その間は日本語の文に英語の語句を残す
    public func rendered(_ level: EnglishLevel) -> MixedTranslation {
        switch level {
        case .japanese:
            return MixedTranslation(text: japanese, kept: [], japanese: japanese)
        case .ninety:
            return englishBased()
        case .ten, .thirty, .fifty:
            return japaneseBased(target: level.rawValue)
        }
    }

    // ✓ の語は必ず英語にし、残りはやさしい語句から順に、英語に戻せる語句(の文字数)の target% まで英語に戻す。
    // 訳全体の文字数を目標にすると、コードや表・製品名の多い文書では語句を全部戻しても届かず、段階どうしが同じになるため
    private func japaneseBased(target: Int) -> MixedTranslation {
        let size = phrases.map { $0.english.filter { !$0.isWhitespace }.count }
        let goal = Double(size.reduce(0, +)) * Double(target) / 100
        var keep = Set(phrases.indices.filter { phrases[$0].isLearned })
        var kept = Double(keep.map { size[$0] }.reduce(0, +))
        for index in phrases.indices.sorted(by: { phrases[$0].difficulty < phrases[$1].difficulty }) where !keep.contains(index) {
            guard kept < goal else { break }
            // 足すと目標から遠ざかるほど長い語句は、飛ばして次の短い語句を試す
            let next = kept + Double(size[index])
            if next - goal > goal - kept { continue }
            keep.insert(index)
            kept = next
        }
        return mixed(keeping: keep)
    }

    private func mixed(keeping keep: Set<Int>) -> MixedTranslation {
        var phraseIndex = -1
        let raw = segments.map { segment -> String in
            switch segment {
            case let .plain(text):
                return text
            case let .phrase(phrase):
                phraseIndex += 1
                return keep.contains(phraseIndex) ? "\(MixedTranslation.open)\(phrase.english) | \(phrase.japanese)\(MixedTranslation.close)" : phrase.japanese
            }
        }.joined()
        let kept = keep.map { phrases[$0] }
        return MixedTranslation.parse(raw, knownTerms: kept.filter(\.isLearned).map(\.english), triedTerms: kept.filter { !$0.isLearned }.map(\.english))
    }

    // 原文のまま読み、難しい語句から順に、全体の 1 割ほどまで日本語を添える。✓ の語は色を付けて見せる
    private func englishBased() -> MixedTranslation {
        var text = source
        let total = source.filter { !$0.isWhitespace }.count
        var glossed = 0
        for phrase in phrases.filter({ !$0.isLearned }).sorted(by: { $0.difficulty > $1.difficulty }) {
            guard glossed * 10 < total else { break }
            let pattern = "(?<![A-Za-z])" + NSRegularExpression.escapedPattern(for: phrase.english) + "(?![A-Za-z])(?!（)"
            guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
            let note = "（\(phrase.japanese)）"
            text.insert(contentsOf: note, at: range.upperBound)
            glossed += note.count
        }
        var kept: [KeptTerm] = []
        for phrase in phrases where phrase.isLearned {
            let pattern = "(?<![A-Za-z])" + NSRegularExpression.escapedPattern(for: phrase.english) + "(?![A-Za-z])"
            guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
                  !kept.contains(where: { $0.term == phrase.english })
            else { continue }
            kept.append(KeptTerm(range: NSRange(range, in: text), english: phrase.english, japanese: phrase.japanese, term: phrase.english, isLearned: true))
        }
        return MixedTranslation(text: text, kept: kept, japanese: japanese, englishOverride: Self.latinCount(text))
    }

    static func latinCount(_ text: String) -> Int {
        text.unicodeScalars.filter { $0.isASCII && CharacterSet.letters.contains($0) || ($0.isASCII && CharacterSet.decimalDigits.contains($0)) }.count
    }
}
