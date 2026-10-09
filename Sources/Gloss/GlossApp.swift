import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// Store をここで1回だけ作って、画面には environment で渡す。依存は settings → history・words → ask・translate の向きだけ
@main
struct GlossApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings: SettingsStore
    @State private var router = RouterStore()
    @State private var history: HistoryStore
    @State private var words: WordsStore
    @State private var ask: AskStore
    @State private var translate: TranslateStore

    init() {
        let settings = SettingsStore()
        let history = HistoryStore()
        let words = WordsStore(settings: settings)
        _settings = State(initialValue: settings)
        _history = State(initialValue: history)
        _words = State(initialValue: words)
        _ask = State(initialValue: AskStore(settings: settings, words: words))
        _translate = State(initialValue: TranslateStore(settings: settings, history: history))
    }

    var body: some Scene {
        Window("Gloss", id: "main") {
            RootPage()
                .environment(settings)
                .environment(router)
                .environment(history)
                .environment(words)
                .environment(ask)
                .environment(translate)
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 1040, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新規翻訳") {
                    translate.reset()
                    router.go(.translate)
                }
                .keyboardShortcut("n")
            }
        }

        Settings {
            SettingsPage()
                .environment(settings)
        }
    }
}
