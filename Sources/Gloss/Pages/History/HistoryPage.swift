import GlossCore
import SwiftUI

// たまにしか見ないので、サイドバーには置かず、ここで一覧にする
struct HistoryPage: View {
    @Environment(HistoryStore.self) private var history

    var body: some View {
        if history.state.items.isEmpty {
            ContentUnavailableView(
                "No history yet",
                systemImage: "clock",
                description: Text("Your translations show up here, newest first.")
            )
        } else {
            List(history.state.items) { item in
                HistoryRow(item: item)
            }
        }
    }
}

private struct HistoryRow: View {
    @Environment(HistoryStore.self) private var history
    @Environment(TranslateStore.self) private var translate
    @Environment(RouterStore.self) private var router
    let item: HistoryItem

    var body: some View {
        Button {
            translate.open(item, image: history.image(for: item))
            router.go(.translate)
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
                        .help("Translated from an image")
                }
                Text(item.date, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open in Translate")
        .contextMenu {
            Button("Delete", role: .destructive) { history.delete(item) }
        }
    }
}
