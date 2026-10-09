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
            if model.showsWords {
                WordsView()
            } else {
                TranslateView()
            }
        }
        .inspector(isPresented: $model.isAskOpen) {
            AskPanel()
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

            if !model.history.isEmpty {
                Section("履歴") {
                    ForEach(model.history) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .lineLimit(1)
                            Text(item.date, format: .relative(presentation: .named))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(SidebarItem.history(item.id))
                        .contextMenu {
                            Button("削除", role: .destructive) { model.deleteHistory(item) }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
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
                    onPasteText: model.didPasteText
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
            GlossTextView(text: .constant(model.translation), isEditable: false, onSelect: model.select)

            if let error = model.translationError {
                VStack(spacing: 12) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("再試行", action: model.translate)
                }
                .padding(24)
            } else if model.translation.isEmpty && !model.isTranslating {
                Text("訳文の単語を選ぶと、意味を質問できます")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if !model.selection.isEmpty {
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
        .animation(.snappy(duration: 0.2), value: model.selection.isEmpty)
    }
}

struct AskPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        if model.focus.isEmpty {
            ContentUnavailableView(
                "語句を選んで質問",
                systemImage: "questionmark.bubble",
                description: Text("原文か訳文の単語を選んで ⌘L を押すと、ここで意味や使い方を聞けます")
            )
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
                Button(action: model.saveFocus) {
                    Label(model.isFocusSaved ? "保存済み" : "単語帳に保存",
                          systemImage: model.isFocusSaved ? "bookmark.fill" : "bookmark")
                }
                .disabled(model.isAsking || model.thread.allSatisfy { $0.role != .assistant || $0.text.isEmpty })
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
        if model.words.isEmpty {
            ContentUnavailableView(
                "単語帳はまだ空です",
                systemImage: "book.closed",
                description: Text("質問した語句を「単語帳に保存」すると、ここに並びます")
            )
        } else {
            List {
                ForEach(model.words) { word in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(word.term)
                            .font(.headline)
                        if !word.context.isEmpty {
                            Text(word.context)
                                .font(.callout)
                                .italic()
                                .foregroundStyle(.secondary)
                        }
                        Text(LocalizedStringKey(word.note))
                            .font(.callout)
                            .lineLimit(4)
                    }
                    .padding(.vertical, 6)
                    .textSelection(.enabled)
                }
                .onDelete(perform: model.deleteWords)
            }
            .listStyle(.inset)
        }
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
            LabeledContent("API キー") {
                let service = model.settings.engine.keychainService
                Text(Keychain.hasKey(service: service) ? "Keychain に保存済み(\(service))" : "未登録(\(service))")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}
