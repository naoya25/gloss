import Foundation

// 単語テストの向き。日本語を見て英語を書くか、英語を見て日本語を書くか
public enum WordDirection: String, CaseIterable, Sendable {
    case toEnglish
    case toJapanese

    public func prompt(for word: WordEntry) -> String {
        self == .toEnglish ? (word.japanese ?? word.term) : (word.english ?? word.term)
    }

    public func expected(for word: WordEntry) -> String {
        self == .toEnglish ? (word.english ?? word.term) : (word.japanese ?? word.term)
    }
}

// 文のテストの種類。日本語のお題を英語で書くか、英文を日本語に訳すか
public enum ExerciseKind: String, CaseIterable, Sendable {
    case writing
    case reading
}

public enum WordQuiz {
    public static let questionCount = 10

    // 覚えていない単語と、しばらく見ていない単語から先に出す
    public static func pick(from words: [WordEntry], count: Int = questionCount) -> [WordEntry] {
        let candidates = words.filter(\.hasCardPair)
        let ordered = candidates.sorted { a, b in
            if a.masteryLevel != b.masteryLevel { return a.masteryLevel.rawValue < b.masteryLevel.rawValue }
            return (a.lastReviewed ?? .distantPast) < (b.lastReviewed ?? .distantPast)
        }
        return Array(ordered.prefix(count * 2)).shuffled().prefix(count).map { $0 }
    }

    // 大文字小文字・前後の記号・空白の数の違いは間違いにしない。
    // 日本語の訳は「知らせて・教えて」のように並べてあるので、どれか1つと同じなら正解にする
    public static func isCorrect(_ answer: String, for word: WordEntry, direction: WordDirection = .toEnglish) -> Bool {
        switch direction {
        case .toEnglish:
            let given = normalize(answer)
            guard !given.isEmpty else { return false }
            return [word.english ?? "", word.term].contains { normalize($0) == given }
        case .toJapanese:
            let given = normalizeJapanese(answer)
            guard !given.isEmpty else { return false }
            let variants = (word.japanese ?? "").components(separatedBy: CharacterSet(charactersIn: "・、,/／;；"))
            return variants.contains { normalizeJapanese($0) == given }
        }
    }

    static func normalizeJapanese(_ text: String) -> String {
        String(text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).contains($0) })
    }

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

// 単語テストの1問の採点。結果はそのまま Book の覚えた度合いになる
public struct WordGrade: Equatable, Sendable {
    public var verdict: Mastery
    public var comment: String

    public init(verdict: Mastery, comment: String = "") {
        self.verdict = verdict
        self.comment = comment
    }
}

public struct WordTestItem: Equatable, Sendable {
    public var number: Int
    public var prompt: String
    public var expected: String
    public var answer: String

    public init(number: Int, prompt: String, expected: String, answer: String) {
        self.number = number
        self.prompt = prompt
        self.expected = expected
        self.answer = answer
    }
}

public struct WritingTask: Equatable, Sendable {
    public var scene: String
    public var task: String
}

public struct WritingGrade: Equatable, Sendable {
    public var score: Int
    public var corrected: String
    public var feedback: String
    public var chunks: [StudyChunk]
}

extension Prompts {
    // 単語帳でまだ覚えていない表現を、お題に混ぜて使わせる
    public static func writingTask(using expressions: [String]) -> String {
        var prompt = """
        あなたはソフトウェア企業で働く日本人のための英作文の先生です。
        社内の業務(Slack のやりとり・プルリクエストの説明やレビュー・会議での発言・メール)で実際に書きそうな内容を1つ選び、
        英語で書かせるお題を日本語で出してください。お題は1〜2文で、具体的な状況と伝える中身を含めてください。
        次の2行だけを出力してください。前置きは付けないでください。
        SCENE: <Slack / PR / 会議 / メール のどれか>
        TASK: <日本語のお題>
        """
        if !expressions.isEmpty {
            prompt += "\nできれば次の表現のどれか1つを自然に使う内容にしてください: " + expressions.joined(separator: ", ")
        }
        return prompt
    }

    // 答えと完全に同じでなかった問題だけを、まとめて AI に採点してもらう。
    // 同じ意味の別の言い方や、日本語訳が同じ別の単語も正解にするため
    public static func wordTestReview(_ items: [WordTestItem], direction: WordDirection = .toEnglish) -> String {
        let task = direction == .toEnglish
            ? "学習者は日本語を見て、それに当たる英語を書きました。\n「想定の答え」と違っても、日本語の意味で同じように使える英語なら正解にしてください。"
            : "学習者は英語を見て、その意味を日本語で書きました。\n「想定の答え」と違っても、この英語の意味として正しい日本語なら正解にしてください。"
        var prompt = """
        英単語テストを採点してください。\(task)
        判定は次の3つです。
        O: 正解(綴りの小さな誤りも含む)
        ?: 惜しい(意味は近いが、品詞・ニュアンス・決まった言い方がずれている)
        X: 不正解
        問題ごとに1行ずつ、次の形式だけを出力してください。コメントは日本語で短く。
        <番号>: <O か ? か X> | <コメント>

        """
        for item in items {
            prompt += "\(item.number). 問題: \(item.prompt) / 想定の答え: \(item.expected) / 学習者の答え: \(item.answer)\n"
        }
        return prompt
    }

    public static func parseWordTestReview(_ raw: String) -> [Int: WordGrade] {
        var grades: [Int: WordGrade] = [:]
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let colon = trimmed.firstIndex(of: ":"), let number = Int(trimmed[..<colon].trimmingCharacters(in: .whitespaces)) else { continue }
            let parts = trimmed[trimmed.index(after: colon)...].split(separator: "|", maxSplits: 1)
            let mark = parts.first.map { $0.trimmingCharacters(in: .whitespaces).uppercased() } ?? ""
            let verdict: Mastery? = switch mark {
            case "O", "○", "◯": .known
            case "?", "？": .unsure
            case "X", "×", "✕": .notYet
            default: nil
            }
            guard let verdict else { continue }
            let comment = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
            grades[number] = WordGrade(verdict: verdict, comment: comment)
        }
        return grades
    }

    public static func readingTask(using expressions: [String]) -> String {
        var prompt = """
        あなたはソフトウェア企業で働く日本人のための英語の先生です。
        社内の業務(Slack のやりとり・プルリクエストの説明やレビュー・会議での発言・メール)で実際に目にしそうな英文を1つ作ってください。
        英文は1〜3文で、ネイティブの同僚が書く自然な英語にしてください。学習者はこれを日本語に訳します。
        次の2行だけを出力してください。前置きは付けないでください。
        SCENE: <Slack / PR / 会議 / メール のどれか>
        TASK: <英文。改行せず1行で>
        """
        if !expressions.isEmpty {
            prompt += "\nできれば次の表現のどれか1つを自然に使ってください: " + expressions.joined(separator: ", ")
        }
        return prompt
    }

    public static func readingReview(task: WritingTask, answer: String) -> String {
        """
        あなたはソフトウェア企業で働く日本人の英語の先生です。下の英文を学習者が日本語に訳しました。英文の意味を正しく読み取れているかを採点してください。
        日本語の上手さではなく、意味・ニュアンス・誰が何をするのかを取り違えていないかで採点してください。
        次の形式で答えてください。
        SCORE: <0〜100 の整数>
        CORRECTED: <自然な日本語の模範訳。改行せず1行で>
        その後に日本語で短く解説してください。読み取れていた点を1つ、取り違えた点を箇条書きで、英文のどこからそう読めるのかを添えて。

        解説の最後に、英文から学習者が覚えておくべき単語やフレーズを、大事な順に1行ずつ次の形式で書いてください。
        句動詞・コロケーション・慣用表現はひとかたまりのまま英文のとおりに書き、中学レベルのやさしい語は書かないでください。
        覚える価値のあるものが無ければ「\(chunkPrefix) なし」とだけ書いてください。
        \(chunkPrefix) <表現> | <短い意味>

        # 場面
        \(task.scene)

        # 英文
        \(task.task)

        # 学習者の訳
        \(answer.prefix(2000))
        """
    }

    public static func parseWritingTask(_ raw: String) -> WritingTask? {
        let fields = labeledLines(raw)
        guard let task = fields["TASK"], !task.isEmpty else { return nil }
        return WritingTask(scene: fields["SCENE"] ?? "", task: task)
    }

    public static func writingReview(task: WritingTask, answer: String) -> String {
        """
        あなたはソフトウェア企業で働く日本人の英語を直す先生です。下のお題に対する学習者の英文を採点してください。
        次の形式で答えてください。
        SCORE: <0〜100 の整数。意味が正しく伝わるか・文法・業務での自然さで採点>
        CORRECTED: <同僚にそのまま送れる自然な英文。改行せず1行で>
        その後に日本語で短く解説してください。良かった点を1つ、直した点を箇条書きで、なぜそう直すのかを添えて。

        解説の最後に、直した英文から学習者が覚えておくべき単語やフレーズを、大事な順に1行ずつ次の形式で書いてください。
        句動詞・コロケーション・慣用表現はひとかたまりのまま書き、中学レベルのやさしい語は書かないでください。
        覚える価値のあるものが無ければ「\(chunkPrefix) なし」とだけ書いてください。
        \(chunkPrefix) <表現> | <短い意味>

        # 場面
        \(task.scene)

        # お題
        \(task.task)

        # 学習者の英文
        \(answer.prefix(2000))
        """
    }

    public static func parseWritingGrade(_ raw: String) -> WritingGrade? {
        var rest: [String] = []
        var score: Int?
        var corrected: String?
        for line in raw.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if score == nil, trimmed.uppercased().hasPrefix("SCORE:") {
                score = Int(trimmed.dropFirst(6).trimmingCharacters(in: .whitespaces).prefix { $0.isNumber })
            } else if corrected == nil, trimmed.uppercased().hasPrefix("CORRECTED:") {
                corrected = trimmed.dropFirst(10).trimmingCharacters(in: .whitespaces)
            } else {
                rest.append(line)
            }
        }
        guard let score, let corrected, !corrected.isEmpty else { return nil }
        let split = splitChunks(rest.joined(separator: "\n"))
        return WritingGrade(score: Swift.max(0, Swift.min(100, score)), corrected: corrected, feedback: split.text, chunks: split.chunks)
    }

    static func labeledLines(_ raw: String) -> [String: String] {
        var fields: [String: String] = [:]
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
            fields[key] = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return fields
    }
}
