import Foundation

// 和訳の中で、英語のまま残した覚えた表現1つ。range は text の中の位置(NSString の UTF-16)
public struct KeptTerm: Equatable, Sendable {
    public var range: NSRange
    public var english: String
    public var japanese: String
    // Book の表記。AI が足した語は英文の表記
    public var term: String
    // Book で ✓ の語か。false は、覚えた語が少ないときに AI が足したやさしい語
    public var isLearned: Bool
}

// 訳の一続きの文字。kept は色を付けた英語、phrase は色を付けずに押せる英語(90%)、revealed は押して日本語にした語句
public struct MixedRun: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case plain, kept, phrase, revealed }
    public var text: String
    public var kind: Kind
    public var term: KeptTerm? = nil

    public init(text: String, kind: Kind, term: KeptTerm? = nil) {
        self.text = text
        self.kind = kind
        self.term = term
    }
}

// 英文を和訳し、覚えた表現(Book で ✓)だけを英語のまま残したもの。
// 覚えた表現が増えるほど、訳の中の英語の割合が上がっていく
public struct MixedTranslation: Equatable, Sendable {
    public var text: String
    public var kept: [KeptTerm]
    // 残した表現も日本語にした、全文の和訳
    public var japanese: String
    // 英語の原文を土台にした訳(90%)では、残した語句ではなく英字の数で英語の割合を数える
    var englishOverride: Int? = nil
    // 英語原文の訳(90%)では、色を付けない語句も押して日本語にできる
    var clickableOverride: [KeptTerm]? = nil

    // 押して日本語にした語句。range は日本語(90% は「英語（日本語）」)の位置で、もう一度押すと英語に戻る
    public internal(set) var revealedTerms: [KeptTerm] = []

    // 押すと日本語になる、英語のままの語句
    public var clickable: [KeptTerm] { clickableOverride ?? kept }

    // その位置にある、押せる語句。英語のままの語句と、日本語にした語句の両方を探す
    public func clickable(at location: Int) -> KeptTerm? {
        (clickable + revealedTerms).first { NSLocationInRange(location, $0.range) }
    }

    // 訳を、普通の文字と押せる語句の並びにしたもの。語句が重なったときは先に始まるほうを取る
    public var runs: [MixedRun] {
        let ns = text as NSString
        let colored = Set(kept.map(\.range.location))
        let back = Set(revealedTerms.map(\.range.location))
        let terms = (clickable + revealedTerms).enumerated()
            .sorted { ($0.element.range.location, $0.offset) < ($1.element.range.location, $1.offset) }
            .map(\.element)
        var runs: [MixedRun] = []
        var at = 0
        for term in terms where term.range.location >= at {
            if term.range.location > at {
                runs.append(MixedRun(text: ns.substring(with: NSRange(location: at, length: term.range.location - at)), kind: .plain))
            }
            let kind: MixedRun.Kind = back.contains(term.range.location) ? .revealed : colored.contains(term.range.location) ? .kept : .phrase
            runs.append(MixedRun(text: ns.substring(with: term.range), kind: kind, term: term))
            at = NSMaxRange(term.range)
        }
        if at < ns.length { runs.append(MixedRun(text: ns.substring(from: at), kind: .plain)) }
        return runs
    }

    public static let open: Character = "⟦"
    public static let close: Character = "⟧"

    // AI は残した表現を「⟦hotfix | 緊急修正⟧」の形で書く。受信途中の書きかけの「⟦…」は出さない。
    // 残してよいのは、覚えた表現(knownTerms)と、やさしい語として選んだ語(triedTerms)だけ。ほかを AI が残したら日本語に戻す。
    // source を渡すと、英文に無い語を AI が残したときも日本語に戻す
    public static func parse(_ raw: String, knownTerms: [String], triedTerms: [String] = [], source: String? = nil) -> MixedTranslation {
        let knownByKey = Dictionary(knownTerms.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let tried = Set(triedTerms.map { $0.lowercased() })
        var text = ""
        var japanese = ""
        var kept: [KeptTerm] = []
        var rest = Substring(raw)
        // 日本語と英語がくっつくと語の切れ目が見えないので、間に空白を入れる
        var spacesNext = false
        func appendPlain(_ piece: Substring) {
            if spacesNext, let first = piece.unicodeScalars.first, isJapanese(first) { text += " " }
            spacesNext = false
            text += piece
        }
        while let start = rest.firstIndex(of: open) {
            appendPlain(rest[..<start])
            japanese += rest[..<start]
            guard let end = rest[start...].firstIndex(of: close) else {
                rest = ""
                break
            }
            let inner = rest[rest.index(after: start)..<end]
            let parts = inner.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            let english = parts.first ?? ""
            let meaning = parts.count > 1 ? parts[1] : english
            japanese += meaning
            let key = english.lowercased()
            let inSource = source.map { contains(english, in: $0) } ?? true
            if !english.isEmpty, inSource, knownByKey[key] != nil || tried.contains(key) {
                if let last = text.unicodeScalars.last, isJapanese(last) || CharacterSet.letters.contains(last) { text += " " }
                let location = (text as NSString).length
                text += english
                kept.append(KeptTerm(
                    range: NSRange(location: location, length: (english as NSString).length),
                    english: english, japanese: meaning, term: knownByKey[key] ?? english, isLearned: knownByKey[key] != nil
                ))
                spacesNext = true
            } else {
                appendPlain(Substring(meaning))
            }
            rest = rest[rest.index(after: end)...]
        }
        appendPlain(rest)
        japanese += rest
        return MixedTranslation(text: text, kept: kept, japanese: japanese)
    }

    // 「Hi」が「this」の中に当たらないように、前後が英字でない場所だけを探す
    public static func contains(_ word: String, in text: String) -> Bool {
        let pattern = "(?<![A-Za-z])" + NSRegularExpression.escapedPattern(for: word) + "(?![A-Za-z])"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // AI が選んだやさしい語の答えから、英文にあって、まだ覚えている途中でもない語だけを取る
    public static func parseEasyWords(_ raw: String, source: String, excluding: [String]) -> [String] {
        let excluded = Set(excluding.map { $0.lowercased() })
        var words: [String] = []
        for line in raw.components(separatedBy: .newlines) {
            let word = line.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-*・")))
            guard !word.isEmpty, !excluded.contains(word.lowercased()), contains(word, in: source),
                  !words.contains(where: { $0.lowercased() == word.lowercased() })
            else { continue }
            words.append(word)
        }
        return words
    }

    // 英語のまま残した表現。同じ表現が2回出ても1つと数える
    public var keptTerms: [String] { unique(kept) }
    public var learnedTerms: [String] { unique(kept.filter(\.isLearned)) }
    public var triedTerms: [String] { unique(kept.filter { !$0.isLearned }) }

    private func unique(_ items: [KeptTerm]) -> [String] {
        var seen: [String] = []
        for item in items where !seen.contains(item.term) { seen.append(item.term) }
        return seen
    }

    // 訳の中の英語の文字の割合(空白を除く)。0〜100
    public var englishCharacters: Int { englishOverride ?? kept.map { $0.english.filter { !$0.isWhitespace }.count }.reduce(0, +) }

    // 英語のまま読んだ点。覚えた語は1語ごとに、ほかは英語の割合 10% ごとに付ける。質問して確かめた語は数えない
    public func readingPoints(excluding asked: Set<String>) -> Int {
        learnedTerms.filter { !asked.contains($0.lowercased()) }.count * Points.perKeptTerm + englishRate / 10 * Points.perTriedTerm
    }
    public var totalCharacters: Int { text.filter { !$0.isWhitespace }.count }
    public var englishRate: Int { totalCharacters == 0 ? 0 : englishCharacters * 100 / totalCharacters }

    // 質問して意味を確かめた表現は、助けを借りたので点にしない
    public func points(excluding asked: Set<String>) -> Int {
        learnedTerms.filter { !asked.contains($0.lowercased()) }.count * Points.perKeptTerm
            + triedTerms.filter { !asked.contains($0.lowercased()) }.count * Points.perTriedTerm
    }

    // 日本語をほとんど含まない英文だけを、覚えた表現を残して訳す対象にする
    public static func isEnglish(_ text: String) -> Bool {
        let latin = text.unicodeScalars.filter { (0x41...0x5A).contains($0.value) || (0x61...0x7A).contains($0.value) }.count
        let japanese = text.unicodeScalars.filter(isJapanese).count
        return latin >= 10 && japanese * 20 < latin
    }

    // 選んだ文から英語のところだけを抜き出す。読み上げの声は英語用なので、日本語は読まずに区切りにする
    public static func englishParts(of text: String) -> String? {
        var parts: [String] = []
        var current = ""
        for scalar in text.unicodeScalars {
            if isJapanese(scalar) || (0x3000...0x303F).contains(scalar.value) || (0xFF01...0xFF65).contains(scalar.value) {
                parts.append(current)
                current = ""
            } else {
                current.unicodeScalars.append(scalar)
            }
        }
        parts.append(current)
        let english = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters.subtracting(CharacterSet(charactersIn: "'’")))) }
            .filter { $0.unicodeScalars.contains { CharacterSet.letters.contains($0) && $0.isASCII } }
        return english.isEmpty ? nil : english.joined(separator: ". ")
    }

    public static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isJapanese)
    }

    static func isJapanese(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x4E00...0x9FFF, 0xFF66...0xFF9F: true
        default: false
        }
    }
}

// 点は記録から数える。訳の中で覚えた表現を英語のまま読めたら1つ10点、AI が足した語なら5点、単語テストで1問正解したら10点
public enum Points {
    public static let perKeptTerm = 10
    public static let perTriedTerm = 5
    public static let perCorrectAnswer = 10

    public static func of(_ event: ActivityEvent) -> Int {
        if let points = event.points { return points }
        switch event.kind {
        case .wordQuiz, .meaningQuiz: return (event.score ?? 0) * perCorrectAnswer
        default: return 0
        }
    }

    public static func total(_ events: [ActivityEvent]) -> Int {
        events.map(of).reduce(0, +)
    }
}
