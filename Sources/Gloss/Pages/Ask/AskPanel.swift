import GlossCore
import SwiftUI

struct AskPanel: View {
    @Environment(AskStore.self) private var ask
    @Environment(RouterStore.self) private var router

    var body: some View {
        if ask.state.focus.isEmpty {
            AskEmptyState(isWords: router.route == .words)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                AskHeader()
                Divider()
                AskThread()
                Divider()
                AskComposer()
            }
        }
    }
}

private struct AskEmptyState: View {
    let isWords: Bool

    var body: some View {
        if isWords {
            ContentUnavailableView(
                "カードをめくると説明が出ます",
                systemImage: "rectangle.on.rectangle",
                description: Text("めくったカードの説明がここに出て、続けて質問できます")
            )
        } else {
            ContentUnavailableView(
                "語句を選んで質問",
                systemImage: "questionmark.bubble",
                description: Text("原文か訳文の単語をダブルクリックするか、フレーズをドラッグで選ぶと、ここで意味や使い方を聞けます")
            )
        }
    }
}

private struct AskHeader: View {
    @Environment(AskStore.self) private var ask
    @Environment(RouterStore.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(ask.state.focus)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)
                    .lineLimit(3)
                Spacer()
            }
            StudyChunks()
            if router.route == .words, let word = ask.focusWord {
                CardDetails(word: word)
            }
            HStack(spacing: 6) {
                ForEach(Prompts.quickQuestions) { quick in
                    Button(quick.label) { ask.send(quick.question(about: ask.state.focus)) }
                        .controlSize(.small)
                        .disabled(ask.state.isAsking)
                }
            }
        }
        .padding(16)
    }
}

// 答えから抜き出した表現を1つずつ並べる。どれも自動で単語帳に入っていて、押すと外す・入れるを切り替える
private struct StudyChunks: View {
    @Environment(AskStore.self) private var ask

    var body: some View {
        if !ask.state.chunks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(ask.state.chunks) { chunk in
                    ChunkToggle(chunk: chunk)
                }
            }
        } else if ask.state.hasAnswer && !ask.state.isAsking {
            Text("単語帳に入れるほどの表現はありませんでした")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ChunkToggle: View {
    @Environment(AskStore.self) private var ask
    let chunk: StudyChunk

    var body: some View {
        let isSaved = ask.isSaved(chunk)
        Button {
            ask.toggleSaved(chunk)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(isSaved ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                Text(chunk.expression)
                    .fontWeight(.medium)
                if !chunk.meaning.isEmpty {
                    Text(chunk.meaning)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
        }
        .buttonStyle(.plain)
        .help(isSaved ? "単語帳に入っています。クリックで外す" : "クリックで単語帳に入れる")
    }
}

// カードの行に収まらない訳・用例・例文は、めくったときにここに出す
private struct CardDetails: View {
    let word: WordEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if word.hasCardPair {
                CardLine(label: "英", text: word.text(for: .english), translation: nil)
                CardLine(label: "日", text: word.text(for: .japanese), translation: nil)
            }
            if !word.context.isEmpty {
                CardLine(label: "用例", text: word.context, translation: nil)
            }
            if let example = word.example, !example.isEmpty {
                CardLine(label: "例文", text: example, translation: word.exampleTranslation)
            }
        }
    }
}

private struct AskThread: View {
    @Environment(AskStore.self) private var ask

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(ask.state.thread) { message in
                        MessageRow(message: message)
                            .id(message.id)
                    }
                    if let error = ask.state.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            .onChange(of: ask.state.thread.last?.text) {
                if let id = ask.state.thread.last?.id { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }
}

private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        switch message.role {
        case .user:
            Text(message.text)
                .font(.callout)
                .foregroundStyle(.secondary)
        default:
            Text(LocalizedStringKey(message.text.isEmpty ? "…" : message.text))
                .lineSpacing(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AskComposer: View {
    @Environment(AskStore.self) private var ask

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("ほかに聞きたいこと", text: Binding(get: { ask.state.draft }, set: ask.setDraft), axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .onSubmit(ask.sendDraft)
            if ask.state.isAsking {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(14)
    }
}
