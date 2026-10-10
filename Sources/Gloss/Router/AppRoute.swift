import Observation
import SwiftUI

enum AppRoute: Hashable, CaseIterable {
    case translate
    case words
    case wordTest
    case meaningTest
    case writingTest
    case readingTest
    case report
    case history

    var title: String {
        switch self {
        case .translate: "Translate"
        case .words: "Book"
        case .wordTest: "Word Test"
        case .meaningTest: "Meaning Test"
        case .writingTest: "Writing Test"
        case .readingTest: "Reading Test"
        case .report: "Report"
        case .history: "History"
        }
    }

    var symbol: String {
        switch self {
        case .translate: "character.bubble"
        case .words: "book.closed"
        case .wordTest: "character.textbox"
        case .meaningTest: "character.book.closed"
        case .writingTest: "pencil.and.list.clipboard"
        case .readingTest: "text.magnifyingglass"
        case .report: "chart.bar.xaxis"
        case .history: "clock"
        }
    }

    // サイドバーでは、テストを Challenge の下にまとめる
    static let challenges: [AppRoute] = [.wordTest, .meaningTest, .writingTest, .readingTest]

    @MainActor @ViewBuilder
    var page: some View {
        switch self {
        case .translate: TranslatePage()
        case .words: WordsPage()
        case .wordTest: WordTestPage(direction: .toEnglish)
        case .meaningTest: WordTestPage(direction: .toJapanese)
        case .writingTest: ExercisePage(kind: .writing)
        case .readingTest: ExercisePage(kind: .reading)
        case .report: ReportPage()
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
