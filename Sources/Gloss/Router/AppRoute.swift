import Observation
import SwiftUI

enum AppRoute: Hashable, CaseIterable {
    case translate
    case words
    case history

    var title: String {
        switch self {
        case .translate: "翻訳"
        case .words: "単語帳"
        case .history: "履歴"
        }
    }

    var symbol: String {
        switch self {
        case .translate: "character.bubble"
        case .words: "book.closed"
        case .history: "clock"
        }
    }

    @MainActor @ViewBuilder
    var page: some View {
        switch self {
        case .translate: TranslatePage()
        case .words: WordsPage()
        case .history: HistoryPage()
        }
    }
}

@MainActor
@Observable
final class RouterStore {
    private(set) var route: AppRoute = .translate

    func go(_ route: AppRoute) {
        self.route = route
    }
}
