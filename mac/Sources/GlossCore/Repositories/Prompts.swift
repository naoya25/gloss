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

    // 翻訳が出たあとに、英語の側から覚える表現を抜き出させる
    public static func extraction(source: String, translation: String) -> String {
        """
        日本語を母語とし、ソフトウェア企業で英語を使って働く学習者のために、下の原文と訳文のうち英語の側から、
        覚えておくべき単語やフレーズをすべて、大事な順に1行ずつ次の形式で書いてください。それ以外は何も出力しないでください。
        \(chunkPrefix) <表現(英文のとおり)> | <短い日本語の意味>
        句動詞・コロケーション・慣用表現・業務でよく使う言い回しは、ひとかたまりのまま書いてください。
        中学レベルのやさしい語・人名や製品名などの固有名詞・コード・URL は書かないでください。
        覚える価値のあるものが無ければ「\(chunkPrefix) なし」とだけ書いてください。

        # 原文
        \(source.prefix(4000))

        # 訳文
        \(translation.prefix(4000))
        """
    }

    // 英文を和訳させ、指定した表現だけを英語のまま残させる。残した表現には和訳も添えさせ、全文の和訳も作れるようにする
    public static func mixedTranslation(keep: [String]) -> String {
        """
        あなたはプロの翻訳者です。入力の英文を、要約・省略せずに自然な日本語へ全文翻訳してください。出力は訳文のみとし、前置きや説明を含めないでください。
        ただし、下の「英語のまま残す表現」が英文の中に出てきたら、その部分は訳さずに英語のまま残し、次の形で書いてください。
        \(MixedTranslation.open)<英文での表記> | <その部分の日本語訳>\(MixedTranslation.close)
        - 英語のまま残した表現の前後は、日本語の文として自然になるよう助詞や語順を整えてください(例: 「\(MixedTranslation.open)hotfix | 緊急修正\(MixedTranslation.close)を出しました」「\(MixedTranslation.open)edge case | 想定外のケース\(MixedTranslation.close)を見落とさないように」)
        - 動詞・形容詞の表現は「〜する」「〜な」を付けるなどして、日本語の文の中で使える形にしてください
        - それ以外の語は、すべて日本語に訳してください。製品名・人名・コード・URL は原文のままで構いませんが、\(MixedTranslation.open)\(MixedTranslation.close)では囲まないでください
        - 入力の英文に無い内容を訳文に足さないでください
        入力が Markdown 記法を含む場合は記法を保ってください。

        # 英語のまま残す表現
        \(keep.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    // 英文を和訳させ、訳の中の英語の語句を全部、英語と日本語の両方で書かせる。
    // どこまで英語で読むかは画面で選ぶので、1回の訳で全部の段階を作れるようにする
    public static func gradedTranslation(known: [String]) -> String {
        """
        あなたはプロの翻訳者です。入力の英文を、要約・省略せずに自然な日本語へ全文翻訳してください。出力は訳文のみとし、前置きや説明を含めないでください。
        ただし、英文の中の意味のある語句(名詞句・動詞句・形容詞・副詞・慣用表現。1〜4語程度)は、訳文の中で全部次の形で書いてください。英文の単語の7割以上が、この形のどれかに入るようにしてください。
        \(MixedTranslation.open)<英文での表記> | <その部分の日本語訳> | <難しさ>\(MixedTranslation.close)
        - 難しさは、日本人のソフトウェアエンジニアにとっての難しさを 1〜5 の整数で書いてください。1: 中学で習う語(meeting, check)、3: 仕事でよく見る語(deploy, deadline)、5: 難しい語や慣用表現(rule of thumb, mitigate)
        - 学習者はこの形の部分を英語のまま読むことがあります。英語のまま差し込んでも日本語の文として自然になるよう、前後の助詞や語順を整えてください(例: 「\(MixedTranslation.open)hotfix | 緊急修正 | 3\(MixedTranslation.close)を出しました」)
        - 動詞は原形(push, migrate)で書き、日本語訳は語幹だけ(プッシュ、移行)にして、「する」「しました」「している」などの活用は形の外に書いてください(例: 「\(MixedTranslation.open)push | プッシュ | 2\(MixedTranslation.close)しました」「\(MixedTranslation.open)migrate | 移行 | 3\(MixedTranslation.close)する予定です」)
        - 形容詞も同じく、「な」「に」は形の外に書いてください(例: 「\(MixedTranslation.open)stable | 安定 | 2\(MixedTranslation.close)な」)
        - 形の中の日本語と同じ言葉を、形の外で繰り返さないでください(誤: 「主な\(MixedTranslation.open)main goal | 主な目標 | 2\(MixedTranslation.close)」)
        - FYI・ASAP などの略語や挨拶も語句として囲んでください
        - 冠詞・前置詞・代名詞・be 動詞だけの部分は囲まず、普通に訳してください。製品名・人名・コード・URL は原文のままにし、囲まないでください
        - 入力の英文に無い内容を訳文に足さないでください
        入力が Markdown 記法を含む場合は記法を保ってください。
        \(known.isEmpty ? "" : "\n# 学習者が覚えた表現(英文に出てきたら、必ずひとかたまりの語句として囲んでください)\n" + known.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    // 覚えた表現が少ない英文で、英語のまま読ませるやさしい語を選ばせる
    public static func easyWords(source: String, count: Int, excluding: [String]) -> String {
        """
        日本語を母語とし、ソフトウェア企業で働く英語学習者が、訳さなくても読めそうなやさしい単語を、下の英文から\(count)つ選んでください。
        名詞か形容詞を選び、英文に出てくる表記のまま1行に1つずつ書いてください。それ以外は何も出力しないでください。
        人名・製品名・コード・URL は選ばないでください。
        \(excluding.isEmpty ? "" : "次の語は選ばないでください: " + excluding.joined(separator: ", "))

        # 英文
        \(source.prefix(4000))
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
    // 用例が無い単語(略語など)は意味を取り違えやすいので、保存してある説明も手がかりとして渡す
    public static func cardPair(term: String, context: String, note: String = "") -> String {
        """
        英単語カードを作ります。ソフトウェア企業の業務で使う語句「\(term)」について、次の4行だけを出力してください。前置きや説明は付けないでください。
        EN: <英語の語句>
        JA: <日本語の短い訳(1〜3語程度)>
        EX: <英語の語句を使った、短く自然な英語の例文。下の文とは別の文>
        EXJA: <その例文の日本語訳>
        語句が英語なら EN はその語句をそのまま書き、語句が日本語なら JA はその語句をそのまま書いてください。
        訳は下の文と説明での意味に合わせてください。例文も業務の場面にしてください。
        文: \(context.isEmpty ? "(なし)" : String(context.prefix(500)))
        説明: \(note.isEmpty ? "(なし)" : String(note.prefix(300)))
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
