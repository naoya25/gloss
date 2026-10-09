import Foundation

public struct QuickQuestion: Identifiable, Sendable {
    public let label: String
    let template: String
    public var id: String { label }

    public func question(about focus: String) -> String {
        template.replacingOccurrences(of: "{focus}", with: focus)
    }
}

public enum Prompts {
    public static let transcriptSeparator = "====="

    public static let quickQuestions: [QuickQuestion] = [
        QuickQuestion(label: "意味", template: "「{focus}」はこの文でどういう意味?"),
        QuickQuestion(label: "ニュアンス", template: "「{focus}」と似た言葉とのニュアンスの違いは?"),
        QuickQuestion(label: "例文", template: "「{focus}」を使った例文を3つ、訳付きで"),
        QuickQuestion(label: "使う場面", template: "「{focus}」はどんな場面で使う? フォーマル度は?"),
    ]

    public static func translation(target: TranslationTarget, hasImage: Bool) -> String {
        var prompt = "あなたはプロの翻訳者です。入力が日本語であれば英語に、英語であれば日本語に全文翻訳してください。"
            + "どちらでもない場合は日本語に翻訳してください。要約・省略・意訳による情報の削減は禁止です。"
            + "出力は訳文のみとし、前置きや説明を含めないでください。"
        switch target {
        case .auto:
            prompt += "入力に複数の言語が混在する場合は、文字量の多い言語を入力言語とみなし、全文をどちらか一方の言語に統一してください。"
        case .japanese:
            prompt += "必ず日本語で出力してください。"
        case .english:
            prompt += "必ず英語で出力してください。"
        }
        prompt += "入力が Markdown 記法を含む場合は記法を保ち、本文だけを翻訳してください。HTML タグは出力しないでください。"
        if hasImage {
            prompt += "入力には画像が含まれます。まず画像内の文字をすべて原文のまま書き起こし、"
                + "次に「\(transcriptSeparator)」だけの行を1行出し、その後に書き起こしの訳文を出力してください。"
                + "文字が無い画像は、書き起こしの代わりに写っている内容を1〜2文で説明してください。"
        }
        return prompt
    }

    public static func tutor(source: String, translation: String, focus: String) -> String {
        """
        あなたは日本語を母語とする人の英語学習を手伝う先生です。
        下の原文と訳文を文脈として、ユーザーが選んだ範囲「\(focus)」についての質問に日本語で答えてください。
        説明は選んだ範囲の全体について行ってください。選んだ範囲の区切り方から誤解していそうなとき
        (例: 句動詞の一部だけを選んでいる)は、それも指摘してください。
        答えは短くまとめ、前置きは付けないでください。英語の例文を出すときは訳を添えてください。

        答えの最後に、選んだ範囲とその前後から、学習者が覚えておくべき単語やフレーズをすべて、大事な順に1行ずつ次の形式で書いてください。
        句動詞・コロケーション・慣用表現は、ひとかたまりのまま書いてください。範囲が表現の途中で切れていたら、正しいひとかたまりを書いてください。
        表現の一部でない冠詞や to は含めないでください。中学レベルのやさしい語や、すでに答えた表現は書かないでください。
        覚える価値のあるものが無ければ「\(chunkPrefix) なし」とだけ書いてください。
        \(chunkPrefix) <表現(原文のまま)> | <短い意味>

        # 原文
        \(source.prefix(4000))

        # 訳文
        \(translation.prefix(4000))
        """
    }

    public static let chunkPrefix = "CHUNK:"

    // 答えから「CHUNK:」の行を抜き出し、画面に出す本文と覚える表現に分ける。
    // 受信途中で最後の行が「CHUNK:」の書きかけなら、その行も本文から外す
    public static func splitChunks(_ raw: String) -> (text: String, chunks: [StudyChunk]) {
        var lines = raw.components(separatedBy: "\n")
        if let last = lines.last?.trimmingCharacters(in: .whitespaces), !last.isEmpty, chunkPrefix.hasPrefix(last) {
            lines.removeLast()
        }
        var body: [String] = []
        var chunks: [StudyChunk] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(chunkPrefix) else {
                body.append(line)
                continue
            }
            let parts = trimmed.dropFirst(chunkPrefix.count).split(separator: "|", maxSplits: 1)
            let expression = parts.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            let meaning = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
            let chunk = StudyChunk(expression: expression, meaning: meaning)
            guard !expression.isEmpty, expression != "なし", !chunks.contains(where: { $0.id == chunk.id }) else { continue }
            chunks.append(chunk)
        }
        return (body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), chunks)
    }

    public struct ImageOutput: Equatable {
        public var transcript: String
        public var translation: String
    }

    public static func splitImageOutput(_ raw: String) -> ImageOutput {
        let lines = raw.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == transcriptSeparator }) else {
            return ImageOutput(transcript: raw.trimmingCharacters(in: .whitespacesAndNewlines), translation: "")
        }
        return ImageOutput(
            transcript: lines[..<index].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            translation: lines[(index + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

public enum Sentence {
    private static let terminators: Set<Character> = [".", "!", "?", "。", "！", "？", "\n"]

    public static func containing(_ focus: String, in text: String) -> String? {
        guard !focus.isEmpty, let range = text.range(of: focus, options: .caseInsensitive) else { return nil }
        var start = range.lowerBound
        while start > text.startIndex {
            let previous = text.index(before: start)
            if terminators.contains(text[previous]) { break }
            start = previous
        }
        var end = range.upperBound
        while end < text.endIndex {
            let character = text[end]
            end = text.index(after: end)
            if terminators.contains(character) { break }
        }
        return text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Prompts {
    public static func cardPair(term: String, context: String) -> String {
        """
        英単語カードを作ります。語句「\(term)」について、次の4行だけを出力してください。前置きや説明は付けないでください。
        EN: <英語の語句>
        JA: <日本語の短い訳(1〜3語程度)>
        EX: <英語の語句を使った、短く自然な英語の例文。下の文とは別の文>
        EXJA: <その例文の日本語訳>
        語句が英語なら EN はその語句をそのまま書き、語句が日本語なら JA はその語句をそのまま書いてください。
        訳は下の文での意味に合わせてください。
        文: \(context.isEmpty ? "(なし)" : String(context.prefix(500)))
        """
    }

    public struct CardContent: Equatable, Sendable {
        public var english: String
        public var japanese: String
        public var example: String
        public var exampleTranslation: String
    }

    public static func parseCardPair(_ raw: String) -> CardContent? {
        var fields: [String: String] = [:]
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
            fields[key] = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard let english = fields["EN"], !english.isEmpty,
              let japanese = fields["JA"], !japanese.isEmpty
        else { return nil }
        return CardContent(
            english: english,
            japanese: japanese,
            example: fields["EX"] ?? "",
            exampleTranslation: fields["EXJA"] ?? ""
        )
    }
}
