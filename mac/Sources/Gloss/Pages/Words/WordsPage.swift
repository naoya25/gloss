import GlossCore
import SwiftUI

struct WordsPage: View {
    @Environment(WordsStore.self) private var words
    @Environment(SettingsStore.self) private var settings
    @Environment(SpeechStore.self) private var speech

    var body: some View {
        Group {
            if words.state.words.isEmpty {
                ContentUnavailableView(
                    "Your Book is empty",
                    systemImage: "book.closed",
                    description: Text("Select words or phrases and ask about them. They show up here automatically.")
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        // 横長のカードを1列に並べる。幅は読みやすい長さで止める
                        LazyVStack(spacing: 8) {
                            ForEach(words.orderedWords) { word in
                                WordCard(word: word, face: settings.state.cardFace, isOpen: words.state.openCardID == word.id)
                                    .id(word.id)
                            }
                        }
                        .frame(maxWidth: 720)
                        .padding(20)
                        .frame(maxWidth: .infinity)
                    }
                    // Listen で読んでいるカードを画面の中に保つ
                    .onChange(of: speech.state.speakingWordID) { _, id in
                        guard speech.state.isListening, let id else { return }
                        withAnimation { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
        .onAppear(perform: words.didOpen)
        .onDisappear(perform: speech.stop)
        .toolbar {
            ToolbarItem {
                Button {
                    speech.state.isListening ? speech.stop() : speech.listen(words.orderedWords)
                } label: {
                    Label(speech.state.isListening ? "Stop" : "Listen", systemImage: speech.state.isListening ? "stop.fill" : "headphones")
                }
                .help(speech.state.isListening ? "Stop listening" : "Read every word and its example aloud, from the top")
                .disabled(words.state.words.isEmpty)
            }
            ToolbarItem {
                Picker("Front Side", selection: Binding(get: { settings.state.cardFace }, set: settings.setCardFace)) {
                    ForEach(CardFace.allCases) { face in
                        Text(face.label).tag(face)
                    }
                }
                .pickerStyle(.segmented)
                .help("Language on the front of the cards")
            }
            ToolbarItem {
                Menu {
                    Picker("Sort", selection: Binding(get: { settings.state.wordSort }, set: words.setSort)) {
                        ForEach(WordSort.allCases) { order in
                            Text(order.label).tag(order)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(settings.state.wordSort.label, systemImage: "arrow.up.arrow.down")
                }
                .help("Sort")
            }
        }
    }
}
