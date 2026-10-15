import Foundation

// Markdown を描画した訳の一続きの文字。block は段落の種類、run は押せる語句(普通の文字は nil)
public struct MarkdownPiece: Equatable, Sendable {
    public enum Block: Equatable, Sendable { case paragraph, heading(Int), code, quote, tableHeader, tableCell }
    public var text: String
    public var block: Block
    public var bold = false
    public var italic = false
    public var code = false
    public var link = false
    public var run: MixedRun? = nil
}

public enum MarkdownText {
    // 見出し・箇条書き・番号・引用・コード・表・太字・リンクのどれかがあれば Markdown として出す
    public static func looksLikeMarkdown(_ text: String) -> Bool {
        let block = #"(?m)^\s{0,3}(#{1,6} |[-*+] |\d+\. |> |```|\|.*\|\s*$)"#
        let inline = #"\*\*[^*\n]+\*\*|\[[^\]\n]+\]\([^)\n]+\)"#
        return text.range(of: block, options: .regularExpression) != nil || text.range(of: inline, options: .regularExpression) != nil
    }

    // 押せる語句を印に置き換えてから Markdown を読み、読んだあとの文字の中の印を語句に戻す。
    // 描画で記号が消えても、語句を文字の位置で探し直さずに済む
    public static func pieces(_ runs: [MixedRun]) -> [MarkdownPiece] {
        let marked = runs.enumerated().map { index, run in run.term == nil ? run.text : "\(open)\(index)\(close)" }.joined()
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: marked, options: options) else {
            return [MarkdownPiece(text: runs.map(\.text).joined(), block: .paragraph)]
        }
        var pieces: [MarkdownPiece] = []
        var previous: PresentationIntent?
        for span in parsed.runs {
            let intent = span.presentationIntent
            let kinds = intent?.components.map(\.kind) ?? []
            if intent != previous {
                if let previous { pieces.append(MarkdownPiece(text: sameRow(previous, intent) ? "\t" : "\n", block: .paragraph)) }
                if let prefix = listPrefix(kinds) { pieces.append(MarkdownPiece(text: prefix, block: .paragraph)) }
                previous = intent
            }
            let inline = span.inlinePresentationIntent ?? []
            let style = MarkdownPiece(
                text: "", block: block(kinds),
                bold: inline.contains(.stronglyEmphasized), italic: inline.contains(.emphasized),
                code: inline.contains(.code), link: span.link != nil
            )
            var text = String(parsed[span.range].characters)
            if case .code = style.block, text.hasSuffix("\n") { text.removeLast() }
            pieces += split(text, style: style, runs: runs)
        }
        return pieces
    }

    static let open: Character = "\u{E000}"
    static let close: Character = "\u{E001}"

    private static func split(_ text: String, style: MarkdownPiece, runs: [MixedRun]) -> [MarkdownPiece] {
        var pieces: [MarkdownPiece] = []
        var rest = Substring(text)
        func plain(_ part: Substring) {
            guard !part.isEmpty else { return }
            var piece = style
            piece.text = String(part)
            pieces.append(piece)
        }
        while let start = rest.firstIndex(of: open), let end = rest[start...].firstIndex(of: close) {
            plain(rest[..<start])
            if let index = Int(rest[rest.index(after: start)..<end]), runs.indices.contains(index) {
                var piece = style
                piece.text = runs[index].text
                piece.run = runs[index]
                pieces.append(piece)
            }
            rest = rest[rest.index(after: end)...]
        }
        plain(rest)
        return pieces
    }

    private static func block(_ kinds: [PresentationIntent.Kind]) -> MarkdownPiece.Block {
        for kind in kinds {
            switch kind {
            case let .header(level): return .heading(level)
            case .codeBlock: return .code
            case .tableHeaderRow: return .tableHeader
            case .tableCell where !kinds.contains(.tableHeaderRow): return .tableCell
            case .blockQuote: return .quote
            default: continue
            }
        }
        return .paragraph
    }

    // 表の同じ行のセルどうしは改行でなくタブで区切る
    private static func sameRow(_ previous: PresentationIntent, _ next: PresentationIntent?) -> Bool {
        func row(_ intent: PresentationIntent?) -> Int? {
            intent?.components.first { component in
                switch component.kind {
                case .tableRow, .tableHeaderRow: true
                default: false
                }
            }?.identity
        }
        guard let left = row(previous) else { return false }
        return left == row(next)
    }

    // 箇条書きの最初の段落にだけ「•」か番号を付け、入れ子の深さだけ字下げする
    private static func listPrefix(_ kinds: [PresentationIntent.Kind]) -> String? {
        guard kinds.count >= 3, case let .listItem(ordinal) = kinds[1] else { return nil }
        let depth = kinds.filter { $0 == .orderedList || $0 == .unorderedList }.count
        let indent = String(repeating: "    ", count: max(depth - 1, 0))
        return kinds[2] == .orderedList ? "\(indent)\(ordinal). " : "\(indent)• "
    }
}
