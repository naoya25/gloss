import Foundation
import GlossCore
import Observation

struct HistoryState {
    var items: [HistoryItem] = []
}

@MainActor
@Observable
final class HistoryStore {
    static let limit = 300

    private(set) var state: HistoryState

    init() {
        state = HistoryState(items: Self.removingDuplicates(JSONFile<[HistoryItem]>(AppPaths.history).load() ?? []))
    }

    // 重複を残さないようにする前の履歴にある同じ文は、いちばん新しい1件だけ残す
    private static func removingDuplicates(_ items: [HistoryItem]) -> [HistoryItem] {
        var kept: [HistoryItem] = []
        for item in items where !kept.contains(where: { item.imageFile == nil && $0.matches(source: item.source, target: item.target ?? .auto) }) {
            kept.append(item)
        }
        return kept
    }

    // 同じ文を同じ翻訳先で訳したことがあれば、その訳を返す
    func cached(source: String, target: TranslationTarget) -> HistoryItem? {
        state.items.first { $0.matches(source: source, target: target) }
    }

    // キャッシュから出した訳は、いま訳したものとして一覧の先頭に上げる
    func touch(_ item: HistoryItem) {
        guard let index = state.items.firstIndex(where: { $0.id == item.id }) else { return }
        var moved = state.items.remove(at: index)
        moved.date = .now
        state.items.insert(moved, at: 0)
        save()
    }

    func record(source: String, translation: String, image: Data?, target: TranslationTarget) {
        guard !translation.isEmpty else { return }
        // 同じ文の古い訳は残さない。訳し直したときは新しい訳だけを一覧に置く
        if image == nil {
            state.items.removeAll { $0.matches(source: source, target: target) }
        }
        var imageFile: String?
        if let image {
            let name = "\(UUID().uuidString).jpg"
            try? FileManager.default.createDirectory(at: AppPaths.images, withIntermediateDirectories: true)
            if (try? image.write(to: AppPaths.images.appendingPathComponent(name))) != nil {
                imageFile = name
            }
        }
        state.items.insert(HistoryItem(source: source, translation: translation, imageFile: imageFile, target: target), at: 0)
        state.items = Array(state.items.prefix(Self.limit))
        save()
    }

    func delete(_ item: HistoryItem) {
        state.items.removeAll { $0.id == item.id }
        if let file = item.imageFile {
            try? FileManager.default.removeItem(at: AppPaths.images.appendingPathComponent(file))
        }
        save()
    }

    func image(for item: HistoryItem) -> Data? {
        item.imageFile.flatMap { try? Data(contentsOf: AppPaths.images.appendingPathComponent($0)) }
    }

    private func save() {
        JSONFile<[HistoryItem]>(AppPaths.history).save(state.items)
    }
}
