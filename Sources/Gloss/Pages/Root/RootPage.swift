import SwiftUI

struct RootPage: View {
    @Environment(RouterStore.self) private var router
    @Environment(AskStore.self) private var ask
    @Environment(TranslateStore.self) private var translate

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            // 同じ画面の型どうし(向きの違う単語テストなど)を行き来しても、開き直したことになるようにする
            router.route.page
                .id(router.route)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        }
        .inspector(isPresented: Binding(get: { ask.state.isPanelOpen }, set: ask.setPanelOpen)) {
            // 中身の最小サイズが質問のたびに変わると、分割ビューの制約更新が止まらず落ちる。
            // 最小サイズを 0 に固定して、列の幅は inspectorColumnWidth だけで決める
            AskPanel()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .inspectorColumnWidth(min: 280, ideal: 340, max: 460)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    translate.reset()
                    router.go(.translate)
                } label: {
                    Label("New Translation", systemImage: "square.and.pencil")
                }
                .help("New translation (⌘N)")
            }
            ToolbarItem {
                Button {
                    ask.setPanelOpen(!ask.state.isPanelOpen)
                } label: {
                    Label("Question Panel", systemImage: "sidebar.trailing")
                }
                .help("Show or hide the question panel")
            }
        }
    }
}

private struct Sidebar: View {
    @Environment(RouterStore.self) private var router
    @Environment(WordsStore.self) private var words
    @State private var showsChallenges = true

    var body: some View {
        List(selection: Binding(get: { router.route }, set: { if let route = $0 { router.go(route) } })) {
            SidebarRow(route: .translate)
            SidebarRow(route: .words, badge: words.state.words.count)
            DisclosureGroup(isExpanded: $showsChallenges) {
                ForEach(AppRoute.challenges, id: \.self) { SidebarRow(route: $0) }
            } label: {
                Label("Challenge", systemImage: "checkmark.seal")
            }
            SidebarRow(route: .report)
            SidebarRow(route: .history)
        }
        .listStyle(.sidebar)
    }
}

private struct SidebarRow: View {
    let route: AppRoute
    var badge = 0

    var body: some View {
        Label(route.title, systemImage: route.symbol)
            .badge(badge)
            .tag(route)
    }
}
