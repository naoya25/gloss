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

// Store をここで1回だけ作って、画面には environment で渡す。依存は settings → activity・history → words → ask・translate・quiz の向きだけ
@main
struct GlossApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings: SettingsStore
    @State private var router = RouterStore()
    @State private var history: HistoryStore
    @State private var words: WordsStore
    @State private var ask: AskStore
    @State private var translate: TranslateStore
    @State private var activity: ActivityStore
    @State private var quiz: QuizStore

    init() {
        let settings = SettingsStore()
        let history = HistoryStore()
        let activity = ActivityStore(settings: settings)
        let words = WordsStore(settings: settings, activity: activity)
        _settings = State(initialValue: settings)
        _history = State(initialValue: history)
        _activity = State(initialValue: activity)
        _words = State(initialValue: words)
        _ask = State(initialValue: AskStore(settings: settings, words: words))
        _translate = State(initialValue: TranslateStore(settings: settings, history: history, activity: activity, words: words))
        _quiz = State(initialValue: QuizStore(settings: settings, words: words, activity: activity))
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
                .environment(activity)
                .environment(quiz)
                .frame(minWidth: 760, minHeight: 480)
                // 別の Mac で増えた単語を、Gloss に戻ってきたときに取ってくる
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    words.sync()
                    activity.sync()
                }
        }
        .defaultSize(width: 1040, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Translation") {
                    translate.reset()
                    router.go(.translate)
                }
                .keyboardShortcut("n")
            }
        }

        Settings {
            SettingsPage()
                .environment(settings)
                .environment(words)
        }
    }
}
