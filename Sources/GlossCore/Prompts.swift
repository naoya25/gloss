import Foundation

public enum TranslationTarget: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case japanese
    case english

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .auto: "自動"
        case .japanese: "日本語へ"
        case .english: "英語へ"
        }
    }
}

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
        下の原文と訳文を文脈として、ユーザーが選んだ語句「\(focus)」についての質問に日本語で答えてください。
        答えは短くまとめ、前置きは付けないでください。英語の例文を出すときは訳を添えてください。

        # 原文
        \(source.prefix(4000))

        # 訳文
        \(translation.prefix(4000))
        """
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
