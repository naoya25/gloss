import GlossCore
import SwiftUI

struct WordsPage: View {
    @Environment(WordsStore.self) private var words
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Group {
            if words.state.words.isEmpty {
                ContentUnavailableView(
                    "Your Book is empty",
                    systemImage: "book.closed",
                    description: Text("Select words or phrases and ask about them. They show up here automatically.")
                )
            } else {
                ScrollView {
                    // 横長のカードを1列に並べる。幅は読みやすい長さで止める
                    LazyVStack(spacing: 8) {
                        ForEach(words.orderedWords) { word in
                            WordCard(word: word, face: settings.state.cardFace, isOpen: words.state.openCardID == word.id)
                        }
                    }
                    .frame(maxWidth: 720)
                    .padding(20)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear(perform: words.didOpen)
        .toolbar {
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
