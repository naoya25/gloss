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

    // 英語のまま読めた割合(0〜100)より1段上の段階。実力よりちょっと英語が多い訳で次の英文を読み、押した分だけ下がる
    public static func above(_ ability: Int) -> EnglishLevel {
        allCases.sorted { $0.rawValue < $1.rawValue }.first { $0.rawValue > ability } ?? .ninety
    }

    public static let readsToRise = 5

    // 1回押さずに読んだだけで上げると、訳しただけで読み忘れた英文でも上がってしまうため、上げるのは直近の平均で決める
    public func next(ability: Int, recent: [Int]) -> (level: EnglishLevel, recent: [Int]) {
        let fallen = Self.above(ability)
        if fallen.rawValue < rawValue { return (fallen, []) }
        let reads = Array((recent + [ability]).suffix(Self.readsToRise))
        let average80 = reads.reduce(0, +) * 5 >= rawValue * 4 * reads.count
        guard reads.count == Self.readsToRise, average80, self != .ninety else { return (self, reads) }
        return (Self.above(rawValue), [])
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

    // その段階で読む訳。日本語の段階は全文の和訳、90% は原文、その間は日本語の文に英語の語句を残す。
    // revealed は読みながら押して日本語にした語句(小文字の英語)
    public func rendered(_ level: EnglishLevel, revealed: Set<String> = []) -> MixedTranslation {
        switch level {
        case .japanese:
            return MixedTranslation(text: japanese, kept: [], japanese: japanese)
        case .ninety:
            return englishBased(revealed: revealed)
        case .ten, .thirty, .fifty:
            return japaneseBased(target: level.rawValue, revealed: revealed)
        }
    }

    // 英語で出した語句のうち、押さずに英語のまま読めた割合を、段階と同じ物差し(0〜100)で返す。
    // 50% で出して半分の語句を押したら 25。日本語の段階は 0
    public func readAbility(_ level: EnglishLevel, revealed: Set<String>) -> Int {
        guard level != .japanese else { return 0 }
        let shown = rendered(level).clickable
        let size = { (item: KeptTerm) in item.english.filter { !$0.isWhitespace }.count }
        let total = shown.map(size).reduce(0, +)
        guard total > 0 else { return level.rawValue }
        let read = shown.filter { !revealed.contains($0.english.lowercased()) }.map(size).reduce(0, +)
        return level.rawValue * read / total
    }

    // ✓ の語は必ず英語にし、残りはやさしい語句から順に、英語に戻せる語句(の文字数)の target% まで英語に戻す。
    // 訳全体の文字数を目標にすると、コードや表・製品名の多い文書では語句を全部戻しても届かず、段階どうしが同じになるため
    private func japaneseBased(target: Int, revealed: Set<String>) -> MixedTranslation {
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
        return mixed(keeping: keep, revealed: revealed)
    }

    // keep の語句を英語で入れ、そのうち押した語句(revealed)は日本語に戻す。日本語に戻した語句も、もう一度押せば英語に戻せるよう位置を持つ
    private func mixed(keeping shown: Set<Int>, revealed: Set<String> = []) -> MixedTranslation {
        var text = ""
        var kept: [KeptTerm] = []
        var back: [KeptTerm] = []
        var spacesNext = false
        var phraseIndex = -1
        func term(_ phrase: GlossedPhrase, _ piece: String) -> KeptTerm {
            KeptTerm(range: NSRange(location: (text as NSString).length, length: (piece as NSString).length), english: phrase.english, japanese: phrase.japanese, term: phrase.english, isLearned: phrase.isLearned)
        }
        for segment in segments {
            var phrase: GlossedPhrase?
            if case let .phrase(item) = segment, shown.contains(phraseIndex + 1) { phrase = item }
            if case .phrase = segment { phraseIndex += 1 }
            if let phrase, !revealed.contains(phrase.english.lowercased()) {
                if let last = text.unicodeScalars.last, MixedTranslation.isJapanese(last) || CharacterSet.letters.contains(last) { text += " " }
                kept.append(term(phrase, phrase.english))
                text += phrase.english
                spacesNext = true
                continue
            }
            let piece: String = switch segment {
            case let .plain(plain): plain
            case let .phrase(item): item.japanese
            }
            if spacesNext, let first = piece.unicodeScalars.first, MixedTranslation.isJapanese(first) { text += " " }
            spacesNext = false
            if let phrase { back.append(term(phrase, piece)) }
            text += piece
        }
        return MixedTranslation(text: text, kept: kept, japanese: japanese, revealedTerms: back)
    }

    // 原文のまま読み、難しい語句から順に、全体の 1 割ほどまで日本語を添える。押した語句にも日本語を添える。
    // 日本語を添えていない語句は押せるようにし、✓ の語は色を付けて見せる
    private func englishBased(revealed: Set<String>) -> MixedTranslation {
        var text = source
        let total = source.filter { !$0.isWhitespace }.count
        var glossed = 0
        func gloss(_ phrase: GlossedPhrase) -> Int {
            let pattern = "(?<![A-Za-z])" + NSRegularExpression.escapedPattern(for: phrase.english) + "(?![A-Za-z])(?!（)"
            guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return 0 }
            let note = "（\(phrase.japanese)）"
            text.insert(contentsOf: note, at: range.upperBound)
            return note.count
        }
        for phrase in phrases.filter({ !$0.isLearned }).sorted(by: { $0.difficulty > $1.difficulty }) {
            guard glossed * 10 < total else { break }
            glossed += gloss(phrase)
        }
        for phrase in phrases where revealed.contains(phrase.english.lowercased()) {
            _ = gloss(phrase)
        }
        // 押して日本語を添えた語句は、もう一度押せば日本語を外せるよう「英語（日本語）」の位置を持つ
        var back: [KeptTerm] = []
        for phrase in phrases where revealed.contains(phrase.english.lowercased()) && !back.contains(where: { $0.english == phrase.english }) {
            let pattern = "(?<![A-Za-z])" + NSRegularExpression.escapedPattern(for: phrase.english) + "（" + NSRegularExpression.escapedPattern(for: phrase.japanese) + "）"
            guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
            back.append(KeptTerm(range: NSRange(range, in: text), english: phrase.english, japanese: phrase.japanese, term: phrase.english, isLearned: phrase.isLearned))
        }
        var clickable: [KeptTerm] = []
        for phrase in phrases where !clickable.contains(where: { $0.english.lowercased() == phrase.english.lowercased() }) {
            let pattern = "(?<![A-Za-z])" + NSRegularExpression.escapedPattern(for: phrase.english) + "(?![A-Za-z])(?!（)"
            guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
            clickable.append(KeptTerm(range: NSRange(range, in: text), english: phrase.english, japanese: phrase.japanese, term: phrase.english, isLearned: phrase.isLearned))
        }
        return MixedTranslation(
            text: text, kept: clickable.filter(\.isLearned), japanese: japanese,
            englishOverride: Self.latinCount(text), clickableOverride: clickable, revealedTerms: back
        )
    }

    static func latinCount(_ text: String) -> Int {
        text.unicodeScalars.filter { $0.isASCII && CharacterSet.letters.contains($0) || ($0.isASCII && CharacterSet.decimalDigits.contains($0)) }.count
    }
}
