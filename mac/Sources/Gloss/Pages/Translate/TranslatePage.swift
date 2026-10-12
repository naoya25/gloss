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
            if let mixed = translate.state.mixed, translate.state.level != .japanese {
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

    // 選んだ段階の訳。「日本語」の段階では、全文の和訳をそのまま出す
    private var mixedText: NSAttributedString? {
        guard let mixed = translate.state.mixed, translate.state.level != .japanese else { return nil }
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

// 訳の中にどれくらい英語を残すかを5段階から選ぶ。読み終えたら記録して、英語の割合に応じた点をもらう
private struct ReadChoiceRow: View {
    @Environment(TranslateStore.self) private var translate

    var body: some View {
        let state = translate.state
        if let graded = state.graded, !graded.phrases.isEmpty, let mixed = state.mixed {
            VStack(spacing: 0) {
                Divider()
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Picker("English", selection: Binding(get: { state.level }, set: translate.setLevel)) {
                            ForEach(EnglishLevel.allCases.reversed()) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .help("How much of the translation to leave in English (⌘1–⌘5)")
                        if state.level != .japanese {
                            KeptSummary(mixed: mixed, phraseCount: graded.phrases.count, level: state.level)
                        }
                    }
                    Spacer()
                    if state.isRead {
                        Label("Read · +\(state.pendingPoints) pt", systemImage: "checkmark.circle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else if !state.isTranslating {
                        Button {
                            translate.markRead()
                        } label: {
                            Text("Done Reading  +\(state.pendingPoints) pt").monospacedDigit()
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: [.command, .shift])
                        .help("Record that you read it at this level (⇧⌘↩)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                // ⌘1〜⌘5 で段階を選ぶ。1 が 90%、5 が日本語
                .background {
                    ForEach(Array(EnglishLevel.allCases.reversed().enumerated()), id: \.offset) { offset, level in
                        Button("") { translate.setLevel(level) }
                            .keyboardShortcut(KeyEquivalent(Character("\(offset + 1)")), modifiers: .command)
                            .hidden()
                    }
                }
            }
            .transition(.opacity)
        }
    }
}

// 段階の % は「英語に戻せる語句のうち何割を英語にするか」。コードや表の多い文書では、訳全体の英語の割合はそれより低くなるので、両方を出す
private struct KeptSummary: View {
    let mixed: MixedTranslation
    let phraseCount: Int
    let level: EnglishLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if level == .ninety {
                Text("The original English, with Japanese for the hardest phrases · \(mixed.englishRate)% of the text in English")
            } else {
                Text("\(Set(mixed.kept.map { $0.english.lowercased() }).count) of \(phraseCount) phrases in English · \(mixed.englishRate)% of the text")
            }
            Text("+\(Points.perTriedTerm) pt per 10% of the text in English")
            if !mixed.learnedTerms.isEmpty {
                Text("Learned (+\(Points.perKeptTerm) pt each): \(mixed.learnedTerms.joined(separator: ", "))")
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(2)
    }
}
