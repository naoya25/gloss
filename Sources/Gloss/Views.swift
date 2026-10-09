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
            if model.showsWords, let word = model.focusWord {
                CardDetails(word: word)
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
                    LazyVStack(spacing: 8) {
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
        // カードは動かさず、文字だけを入れ替える。表の文字は一文字ずつぼやけながら上へ抜け、
        // 裏の文字は下から浮かび上がる。横長のカードを回すと動く距離が長くなるため
        CardSurface(isOpen: isOpen) {
            ZStack(alignment: .leading) {
                cardText(word.hasCardPair ? word.text(for: face) : word.term, shown: !isOpen, rise: -1)
                cardText(word.hasCardPair ? word.text(for: backFace) : word.term, shown: isOpen, rise: 1)
            }
            Spacer(minLength: 12)
            ZStack(alignment: .trailing) {
                frontInfo
                    .opacity(isOpen ? 0 : 1)
                    .blur(radius: isOpen && !reduceMotion ? 4 : 0)
                    .allowsHitTesting(!isOpen)
                masteryPicker
                    .opacity(isOpen ? 1 : 0)
                    .blur(radius: !isOpen && !reduceMotion ? 4 : 0)
                    .allowsHitTesting(isOpen)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { model.flipCard(word.id) }
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .timingCurve(0.22, 1, 0.36, 1, duration: 0.7), value: isOpen)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isOpen ? "表に戻す" : "裏返して訳を見る")
        .contextMenu {
            Button("訳と例文を作り直す") { model.regenerateCard(word.id) }
            Button("単語帳から削除", role: .destructive) { model.deleteWord(word.id) }
        }
    }

    @ViewBuilder private func cardText(_ text: String, shown: Bool, rise: Double) -> some View {
        let label = Text(text)
            .font(.title3.weight(.semibold))
        if #available(macOS 15, *) {
            label
                .textRenderer(GlyphRise(progress: shown ? 1 : 0, direction: rise, moves: !reduceMotion))
                .lineLimit(1)
                .accessibilityHidden(!shown)
        } else {
            label
                .opacity(shown ? 1 : 0)
                .lineLimit(1)
                .accessibilityHidden(!shown)
        }
    }

    // 表の右側は、覚えた度合いの印・めくった回数・最後にめくった日だけ。言葉の説明はマウスを乗せたときに出す
    private var frontInfo: some View {
        HStack(spacing: 10) {
            status
            Image(systemName: word.masteryLevel.symbol)
                .foregroundStyle(word.masteryLevel.tint)
            Text(reviewSummary)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.callout)
        .help(reviewHelp)
    }

    private var masteryPicker: some View {
        Picker("覚えた度合い", selection: Binding(
            get: { word.masteryLevel },
            set: { model.setMastery($0, for: word.id) }
        )) {
            ForEach(Mastery.allCases) { level in
                Label(level.label, systemImage: level.symbol)
                    .labelStyle(.iconOnly)
                    .tag(level)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("覚えた度合い: ✕ 覚えてない / ? あやしい / ✓ 覚えた")
    }

    // 1行に収めるため、作成中と失敗は文ではなく印で出し、理由はマウスを乗せたときに出す
    @ViewBuilder private var status: some View {
        if word.isCardComplete {
            EmptyView()
        } else if let error = word.cardError {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
                .help("訳と例文を作れませんでした(\(error))。右クリックで作り直せます")
        } else if word.engine != model.settings.engine {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
                .help("右クリックの「訳と例文を作り直す」で、今のエンジンで作れます")
        } else {
            ProgressView()
                .controlSize(.mini)
                .help("訳と例文を作成中")
        }
    }

    private var reviewSummary: String {
        guard let date = word.lastReviewed else { return "0回" }
        return "\(word.flipCount)回 · \(Self.daysAgo(date))"
    }

    private var reviewHelp: String {
        let last = word.lastReviewed.map { $0.formatted(.dateTime.year().month().day()) } ?? "まだめくっていない"
        return "\(word.masteryLevel.label)・めくった回数 \(word.flipCount)回・最後にめくった日 \(last)"
    }

    static func daysAgo(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: .now)).day ?? 0
        switch days {
        case ..<1: return "今日"
        case 1: return "昨日"
        default: return "\(days)日前"
        }
    }
}

extension Mastery {
    var symbol: String {
        switch self {
        case .notYet: "xmark"
        case .unsure: "questionmark"
        case .known: "checkmark"
        }
    }

    var tint: Color {
        switch self {
        case .notYet: .secondary
        case .unsure: .orange
        case .known: .green
        }
    }
}

// 文字を一文字ずつ時間差で出し入れする。消えるときはぼやけながら direction の向きへ抜け、
// 出るときは反対側から浮かび上がる
@available(macOS 15, *)
struct GlyphRise: TextRenderer, Animatable {
    var progress: Double
    let direction: Double
    let moves: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let glyphs = layout.flatMap { line in line.flatMap { run in run } }
        // 文字数が多くても全体の長さが変わらないよう、時間差は全体の 40% に収める
        let stagger = 0.4
        for (index, glyph) in glyphs.enumerated() {
            let start = glyphs.count > 1 ? stagger * Double(index) / Double(glyphs.count - 1) : 0
            let t = min(max((progress - start) / (1 - stagger), 0), 1)
            var copy = context
            copy.opacity = t
            if moves {
                // 出るときは下から、消えるときは上へ。progress が減る向きでは direction を逆にしない
                copy.translateBy(x: 0, y: (1 - t) * 9 * direction)
                copy.addFilter(.blur(radius: (1 - t) * 5))
            }
            copy.draw(glyph)
        }
    }
}

// カードの裏に収まらない訳・用例・例文は、めくったときに右のパネルに出す
struct CardDetails: View {
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

// 裏を開いているカードは、縁と下地にほんのりアクセント色を差して、どれを開いているか分かるようにする
struct CardSurface<Content: View>: View {
    var isOpen = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) { content }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(isOpen ? 0.08 : 0)))
            }
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isOpen ? AnyShapeStyle(Color.accentColor.opacity(0.5)) : AnyShapeStyle(.separator)))
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
