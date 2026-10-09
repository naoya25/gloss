import GlossCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            Group {
                if model.showsWords {
                    WordsView()
                } else if model.showsHistory {
                    HistoryView()
                } else {
                    TranslateView()
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .inspector(isPresented: $model.isAskOpen) {
            // 中身の最小サイズが質問のたびに変わると、分割ビューの制約更新が止まらず落ちる。
            // 最小サイズを 0 に固定して、列の幅は inspectorColumnWidth だけで決める
            AskPanel()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .inspectorColumnWidth(min: 280, ideal: 340, max: 460)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    model.newTranslation()
                } label: {
                    Label("新規翻訳", systemImage: "square.and.pencil")
                }
                .help("新規翻訳(⌘N)")
            }
            ToolbarItem {
                Button {
                    model.isAskOpen.toggle()
                } label: {
                    Label("質問パネル", systemImage: "sidebar.trailing")
                }
                .help("質問パネルの表示を切り替え")
            }
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebarSelection) {
            Label("翻訳", systemImage: "character.bubble")
                .tag(SidebarItem.current)
            Label("単語帳", systemImage: "book.closed")
                .badge(model.words.count)
                .tag(SidebarItem.words)
            Label("履歴", systemImage: "clock")
                .tag(SidebarItem.history)
        }
        .listStyle(.sidebar)
    }
}

// たまにしか見ないので、サイドバーには置かず、ここで一覧にする
struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.history.isEmpty {
            ContentUnavailableView(
                "履歴はまだありません",
                systemImage: "clock",
                description: Text("翻訳すると、ここに新しい順で並びます")
            )
        } else {
            List(model.history) { item in
                Button {
                    model.openHistory(item)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .lineLimit(1)
                            Text(item.translation)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 12)
                        if item.imageFile != nil {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                                .help("画像から翻訳")
                        }
                        Text(item.date, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("翻訳画面で開く")
                .contextMenu {
                    Button("削除", role: .destructive) { model.deleteHistory(item) }
                }
            }
        }
    }
}

struct TranslateView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            source
            controls
            Divider()
            result
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var source: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 0) {
            if let data = model.sourceImage, let image = NSImage(data: data) {
                HStack(alignment: .top, spacing: 8) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
                    Button {
                        model.removeImage()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("画像を外す")
                }
                .padding([.horizontal, .top], 16)
            }
            ZStack(alignment: .topLeading) {
                GlossTextView(
                    text: $model.sourceText,
                    onSelect: model.select,
                    onImage: model.setImage,
                    onPasteText: model.didPasteText,
                    onMouseSelect: model.askAboutMouseSelection
                )
                if model.sourceText.isEmpty {
                    Text(model.sourceImage == nil ? "文章か画像を ⌘V で貼り付け" : "画像の文字がここに書き起こされます")
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

    private var controls: some View {
        @Bindable var model = model
        return HStack(spacing: 12) {
            Picker("翻訳先", selection: $model.settings.target) {
                ForEach(TranslationTarget.allCases) { target in
                    Text(target.label).tag(target)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Spacer()

            if model.isTranslating {
                ProgressView()
                    .controlSize(.small)
            }
            Button("翻訳", action: model.translate)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!model.canTranslate)
                .help("翻訳(⌘↩)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var result: some View {
        ZStack {
            GlossTextView(
                text: .constant(model.translation),
                isEditable: false,
                onSelect: model.select,
                onMouseSelect: model.askAboutMouseSelection
            )

            if let error = model.translationError {
                VStack(spacing: 12) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("再試行", action: model.translate)
                }
                .padding(24)
            } else if model.translation.isEmpty && !model.isTranslating {
                Text("単語やフレーズを選ぶと、意味を質問できます")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            // マウスで選んだときはもう質問しているので、キーボードで選んだときだけボタンを出す
            if !model.selection.isEmpty, model.selection != model.focus {
                Button(action: model.askAboutSelection) {
                    Label("「\(model.selection.prefix(24))」について質問", systemImage: "questionmark.bubble")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("l", modifiers: .command)
                .help("選んだ語句を質問(⌘L)")
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.2), value: model.selection.isEmpty || model.selection == model.focus)
    }
}

struct AskPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        if model.focus.isEmpty {
            if model.showsWords {
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
        } else {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(model.thread) { message in
                                MessageRow(message: message)
                                    .id(message.id)
                            }
                            if let error = model.askError {
                                Label(error, systemImage: "exclamationmark.triangle")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: model.thread.last?.text) {
                        if let id = model.thread.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
                Divider()
                composer
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.focus)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)
                    .lineLimit(3)
                Spacer()
                // 最初の答えが出た時点で自動保存されるので、ボタンは外す/戻すの切り替えだけ
                Button {
                    model.isFocusSaved ? model.removeFocus() : model.saveFocus()
                } label: {
                    Label(model.isFocusSaved ? "単語帳に保存済み" : "単語帳に戻す",
                          systemImage: model.isFocusSaved ? "bookmark.fill" : "bookmark")
                }
                .help(model.isFocusSaved ? "クリックで単語帳から外す" : "クリックで単語帳に保存")
                .disabled(model.thread.allSatisfy { $0.role != .assistant || $0.text.isEmpty })
            }
            HStack(spacing: 6) {
                ForEach(Prompts.quickQuestions) { quick in
                    Button(quick.label) { model.send(quick.question(about: model.focus)) }
                        .controlSize(.small)
                        .disabled(model.isAsking)
                }
            }
        }
        .padding(16)
    }

    private var composer: some View {
        @Bindable var model = model
        return HStack(alignment: .bottom, spacing: 8) {
            TextField("ほかに聞きたいこと", text: $model.askDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .onSubmit(model.sendDraft)
            if model.isAsking {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(14)
    }
}

struct MessageRow: View {
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

struct WordsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.words.isEmpty {
                ContentUnavailableView(
                    "単語帳はまだ空です",
                    systemImage: "book.closed",
                    description: Text("単語やフレーズを選んで質問すると、ここに自動で並びます")
                )
            } else {
                ScrollView {
                    // 横長のカードを1列に並べる。幅は読みやすい長さで止める
                    LazyVStack(spacing: 12) {
                        ForEach(model.orderedWords) { word in
                            WordCard(word: word, face: model.settings.cardFace, isOpen: model.openCardID == word.id)
                        }
                    }
                    .frame(maxWidth: 720)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Picker("表に出す言語", selection: $model.settings.cardFace) {
                    ForEach(CardFace.allCases) { face in
                        Text(face.label).tag(face)
                    }
                }
                .pickerStyle(.segmented)
                .help("カードの表に出す言語")
            }
            ToolbarItem {
                Menu {
                    Picker("並び替え", selection: Binding(get: { model.settings.wordSort }, set: model.setWordSort)) {
                        ForEach(WordSort.allCases) { order in
                            Text(order.label).tag(order)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(model.settings.wordSort.label, systemImage: "arrow.up.arrow.down")
                }
                .help("並び替え")
            }
        }
    }
}

struct WordCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let word: WordEntry
    let face: CardFace
    let isOpen: Bool

    private var backFace: CardFace { face == .english ? .japanese : .english }

    var body: some View {
        // 中身の多い裏でカードの大きさを決め、表はその上に重ねて同じ大きさにする
        back
            .opacity(isOpen ? 1 : 0)
            .rotation3DEffect(.degrees(reduceMotion ? 0 : (isOpen ? 0 : -180)), axis: (0, 1, 0))
            .overlay {
                front
                    .opacity(isOpen ? 0 : 1)
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : (isOpen ? 180 : 0)), axis: (0, 1, 0))
            }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { model.flipCard(word.id) }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(duration: 0.4), value: isOpen)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isOpen ? "表に戻す" : "裏返して答えを見る")
        .contextMenu {
            Button("訳と例文を作り直す") { model.regenerateCard(word.id) }
            Button("単語帳から削除", role: .destructive) { model.deleteWord(word.id) }
        }
    }

    private var cardStatus: String? {
        if word.isCardComplete { return nil }
        if let error = word.cardError { return "訳と例文を作れませんでした(\(error))。右クリックで作り直せます" }
        if word.engine != model.settings.engine { return "右クリックの「訳と例文を作り直す」で、今のエンジンで作れます" }
        return "訳と例文を作成中…"
    }

    private var front: some View {
        CardSurface {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(word.hasCardPair ? word.text(for: face) : word.term)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                    if let status = cardStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 16)
                stats
            }
        }
    }

    private var back: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(word.hasCardPair ? word.text(for: backFace) : word.term)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Spacer(minLength: 16)
                    Picker("覚えた度合い", selection: Binding(
                        get: { word.masteryLevel },
                        set: { model.setMastery($0, for: word.id) }
                    )) {
                        ForEach(Mastery.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                }
                if !word.context.isEmpty {
                    CardLine(label: "用例", text: word.context, translation: nil)
                }
                if let example = word.example, !example.isEmpty {
                    CardLine(label: "例文", text: example, translation: word.exampleTranslation)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stats: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(word.masteryLevel.label)
                .font(.caption.weight(.medium))
            Group {
                if let date = word.lastReviewed {
                    Text("最後にめくった日 \(date.formatted(.dateTime.year().month().day()))")
                } else {
                    Text("まだめくっていない")
                }
                Text("めくった回数 \(word.flipCount)回")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
    }
}

struct CardLine: View {
    let label: String
    let text: String
    let translation: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if let translation, !translation.isEmpty {
                    Text(translation)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct CardSurface<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Picker("翻訳エンジン", selection: $model.settings.engine) {
                ForEach(Engine.allCases) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            .onChange(of: model.settings.engine) { _, engine in
                model.settings.model = engine.defaultModel
            }
            TextField("モデル", text: $model.settings.model)
            if model.settings.engine == .jai {
                TextField("ユーザーID", text: $model.settings.jaiUserID, prompt: Text("会社のメールアドレス"))
            }
            APIKeyField(service: model.settings.engine.keychainService)
                .id(model.settings.engine)
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}

// 入力したキーは Keychain に保存する。保存済みのキーは画面に出さない
struct APIKeyField: View {
    let service: String
    @State private var draft = ""
    @State private var isSaved = false
    @State private var failed = false

    var body: some View {
        LabeledContent("API キー") {
            HStack(spacing: 8) {
                SecureField("API キー", text: $draft, prompt: Text(isSaved ? "保存済み(変えるときだけ入力)" : "貼り付けて保存"))
                    .labelsHidden()
                    .onSubmit(save)
                Button("保存", action: save)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .task { isSaved = Keychain.hasKey(service: service) }
        if failed {
            Text(failureMessage)
                .font(.caption)
                .foregroundStyle(.red)
        } else {
            Text(isSaved ? "Keychain に保存済み(\(service))" : "未登録(\(service))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var failureMessage: String {
        Keychain.isAcceptableKey(draft) || draft.isEmpty
            ? "Keychain に保存できませんでした"
            : "改行などの制御文字を含むキーは保存できません"
    }

    private func save() {
        failed = !Keychain.setAPIKey(draft, service: service)
        if !failed { draft = "" }
        isSaved = Keychain.hasKey(service: service)
    }
}
