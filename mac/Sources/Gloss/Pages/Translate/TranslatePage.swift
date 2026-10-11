import GlossCore
import SwiftUI

struct TranslatePage: View {
    var body: some View {
        VStack(spacing: 0) {
            SourceEditor()
            TranslateControls()
            Divider()
            TranslationResult()
            ReadChoiceRow()
            ExtractedWords()
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct SourceEditor: View {
    @Environment(TranslateStore.self) private var translate
    @Environment(AskStore.self) private var ask

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let data = translate.state.sourceImage, let image = NSImage(data: data) {
                AttachedImage(image: image)
            }
            GlossTextView(
                text: Binding(get: { translate.state.sourceText }, set: translate.setSourceText),
                onSelect: translate.select,
                onImage: translate.setImage,
                onPasteText: translate.didPasteText,
                onMouseSelect: {
                    translate.noteAsked($0)
                    ask.askAboutMouseSelection($0, source: translate.state.sourceText, translation: translate.state.translation)
                }
            )
            .overlay(alignment: .topLeading) {
                if translate.state.sourceText.isEmpty {
                    Text(translate.state.sourceImage == nil ? "Paste text or an image with ⌘V" : "Text in the image will appear here")
                        .font(.system(size: 15))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 21)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(minHeight: 120, idealHeight: 200)
    }
}

private struct AttachedImage: View {
    @Environment(TranslateStore.self) private var translate
    let image: NSImage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 96)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            Button(action: translate.removeImage) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove image")
        }
        .padding([.horizontal, .top], 16)
    }
}

private struct TranslateControls: View {
    @Environment(TranslateStore.self) private var translate
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        HStack(spacing: 12) {
            Picker("Target", selection: Binding(get: { settings.state.target }, set: settings.setTarget)) {
                ForEach(TranslationTarget.allCases) { target in
                    Text(target.label).tag(target)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer()

            if translate.state.isFromCache {
                CacheBadge()
            }
            if let mixed = translate.state.mixed, translate.state.choice != .translatedAll, !mixed.kept.isEmpty {
                Text("English \(mixed.englishRate)%")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.tint)
                    .help("Share of this translation left in English, because you already know those words")
            }
            if translate.state.isTranslating {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Translate") { translate.translate() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!translate.state.canTranslate)
                .help("Translate (⌘↩)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// 前に訳した文と同じなので、AI に送らず履歴の訳を出したことを示す。押すと訳し直す
private struct CacheBadge: View {
    @Environment(TranslateStore.self) private var translate

    var body: some View {
        Button {
            translate.translate(force: true)
        } label: {
            Label("From History", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .foregroundStyle(.secondary)
        .help("Showing your earlier translation of the same text. Click to translate it again.")
    }
}

private struct TranslationResult: View {
    @Environment(TranslateStore.self) private var translate
    @Environment(AskStore.self) private var ask

    // マウスで選んだときはもう質問しているので、キーボードで選んだときだけボタンを出す
    private var showsAskButton: Bool {
        !translate.state.selection.isEmpty && translate.state.selection != ask.state.focus
    }

    // 覚えた表現を英語のまま残した訳。「全部日本語に」を選んだら、全文の和訳に切り替える
    private var mixedText: NSAttributedString? {
        guard let mixed = translate.state.mixed, translate.state.choice != .translatedAll, !mixed.kept.isEmpty else { return nil }
        return MixedText.make(mixed)
    }

    var body: some View {
        GlossTextView(
            text: .constant(translate.state.translation),
            attributedText: mixedText,
            isEditable: false,
            onSelect: translate.select,
            onMouseSelect: {
                translate.noteAsked($0)
                ask.askAboutMouseSelection($0, source: translate.state.sourceText, translation: translate.state.translation)
            }
        )
        .overlay { ResultMessage() }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if showsAskButton {
                AskSelectionButton()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: showsAskButton)
    }
}

// 訳が出たあとに Book に入れた表現を、訳文の下に1行で並べる。押すと外せる
private struct ExtractedWords: View {
    @Environment(TranslateStore.self) private var translate

    var body: some View {
        let state = translate.state
        if state.isExtracting || !state.extracted.isEmpty {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 10) {
                    Label("Added to Book", systemImage: "bookmark.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    if state.isExtracting {
                        ProgressView().controlSize(.small)
                        Text("Finding words to learn…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(state.extracted) { chunk in
                                    ExtractedChip(chunk: chunk)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .transition(.opacity)
        }
    }
}

private struct ExtractedChip: View {
    @Environment(TranslateStore.self) private var translate
    @Environment(WordsStore.self) private var words
    let chunk: StudyChunk

    var body: some View {
        let isSaved = words.entry(for: chunk.expression) != nil
        Button {
            translate.toggleSaved(chunk)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(isSaved ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                Text(chunk.expression)
                    .foregroundStyle(isSaved ? .primary : .secondary)
                    .strikethrough(!isSaved)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(Capsule().strokeBorder(.separator))
        }
        .buttonStyle(.plain)
        .help(chunk.meaning.isEmpty
            ? (isSaved ? "In your Book. Click to remove it" : "Click to add it back")
            : "\(chunk.meaning) — \(isSaved ? "click to remove it from your Book" : "click to add it back")")
    }
}

private struct ResultMessage: View {
    @Environment(TranslateStore.self) private var translate

    var body: some View {
        if let error = translate.state.error {
            VStack(spacing: 12) {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") { translate.translate(force: true) }
            }
            .padding(24)
        } else if translate.state.translation.isEmpty && !translate.state.isTranslating {
            Text("Select a word or phrase to ask about it")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .allowsHitTesting(false)
        }
    }
}

private struct AskSelectionButton: View {
    @Environment(TranslateStore.self) private var translate
    @Environment(AskStore.self) private var ask

    var body: some View {
        Button {
            ask.ask(about: translate.state.selection, source: translate.state.sourceText, translation: translate.state.translation)
        } label: {
            Label("Ask about “\(translate.state.selection.prefix(24))”", systemImage: "questionmark.bubble")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut("l", modifiers: .command)
        .help("Ask about the selection (⌘L)")
        .padding(.bottom, 16)
    }
}

// 英語のまま残した表現は太字の色付きにする。指を置くと日本語が出る
enum MixedText {
    static func make(_ mixed: MixedTranslation) -> NSAttributedString {
        let result = NSMutableAttributedString(string: mixed.text, attributes: GlossTextView.attributes)
        for item in mixed.kept {
            result.addAttributes([
                .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
                .foregroundColor: NSColor.controlAccentColor,
                .toolTip: item.japanese,
            ], range: item.range)
        }
        return result
    }
}

// 英語を残した訳を読み終えたら、どちらかを選ぶ。このまま読めたら点、全部日本語にしたら点なし
private struct ReadChoiceRow: View {
    @Environment(TranslateStore.self) private var translate

    var body: some View {
        let state = translate.state
        if let mixed = state.mixed, !mixed.kept.isEmpty, !state.isTranslating {
            VStack(spacing: 0) {
                Divider()
                Group {
                    switch state.choice {
                    case nil:
                        VStack(alignment: .leading, spacing: 10) {
                            KeptSummary(mixed: mixed)
                            HStack(spacing: 12) {
                                ChoiceButton(symbol: "checkmark", title: "Read It As Is", points: state.pendingPoints, isPrimary: true, action: translate.keepEnglish)
                                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                                ChoiceButton(symbol: "character.bubble", title: "Translate All", points: 0, isPrimary: false, action: translate.translateAll)
                            }
                        }
                    case .keptEnglish:
                        Label("+\(state.pendingPoints) pt — you read \(mixed.englishRate)% of it in English", systemImage: "star.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .translatedAll:
                        Label("Showing everything in Japanese. No points for this one.", systemImage: "character.bubble")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .transition(.opacity)
        }
    }
}

private struct ChoiceButton: View {
    let symbol: String
    let title: String
    let points: Int
    let isPrimary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(isPrimary ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                Text(title).font(.body.weight(.medium))
                Text("+\(points) pt")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(points > 0 ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isPrimary ? AnyShapeStyle(.green.opacity(0.5)) : AnyShapeStyle(.separator)))
    }
}

// 英語のまま残した語を、覚えた語と、AI が足したやさしい語に分けて出す
private struct KeptSummary: View {
    let mixed: MixedTranslation

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !mixed.learnedTerms.isEmpty {
                Text("Learned (+\(Points.perKeptTerm) pt each): \(mixed.learnedTerms.joined(separator: ", "))")
            }
            if !mixed.triedTerms.isEmpty {
                Text("Easy words to try (+\(Points.perTriedTerm) pt each): \(mixed.triedTerms.joined(separator: ", "))")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
}
