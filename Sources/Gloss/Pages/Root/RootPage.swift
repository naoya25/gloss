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
            router.route.page
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
                    Label("新規翻訳", systemImage: "square.and.pencil")
                }
                .help("新規翻訳(⌘N)")
            }
            ToolbarItem {
                Button {
                    ask.setPanelOpen(!ask.state.isPanelOpen)
                } label: {
                    Label("質問パネル", systemImage: "sidebar.trailing")
                }
                .help("質問パネルの表示を切り替え")
            }
        }
    }
}

private struct Sidebar: View {
    @Environment(RouterStore.self) private var router
    @Environment(WordsStore.self) private var words

    var body: some View {
        List(selection: Binding(get: { router.route }, set: { if let route = $0 { router.go(route) } })) {
            ForEach(AppRoute.allCases, id: \.self) { route in
                Label(route.title, systemImage: route.symbol)
                    .badge(route == .words ? words.state.words.count : 0)
                    .tag(route)
            }
        }
        .listStyle(.sidebar)
    }
}
