import Foundation
import GlossCore
import Observation

struct ActivityState {
    var events: [ActivityEvent] = []
}

// 学習の記録は Cloudflare の activity テーブルを正とする。activity.json は電波が無いときの控え
@MainActor
@Observable
final class ActivityStore {
    static let limit = 20_000

    private(set) var state: ActivityState
    private let settings: SettingsStore
    private var ledger: ActivityLedger
    private var isSyncing = false
    private var syncAgain = false
    private var pushTask: Task<Void, Never>?

    init(settings: SettingsStore) {
        self.settings = settings
        let events = JSONFile<[ActivityEvent]>(AppPaths.activity).load() ?? []
        state = ActivityState(events: events)
        ledger = JSONFile<ActivityLedger>(AppPaths.activitySync).load() ?? .initial(for: events)
        sync()
    }

    func record(_ event: ActivityEvent) {
        state.events.append(event)
        if state.events.count > Self.limit {
            state.events.removeFirst(state.events.count - Self.limit)
        }
        ledger.pending.insert(event.id.uuidString)
        save()
        pushTask?.cancel()
        pushTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            sync()
        }
    }

    func record(_ kind: ActivityKind, title: String, score: Int? = nil, total: Int? = nil, detail: String? = nil, wordID: UUID? = nil) {
        record(ActivityEvent(kind: kind, title: title, score: score, total: total, detail: detail, wordID: wordID))
    }

    func report(on day: Date = .now) -> DayReport {
        DayReport(events: state.events, on: day)
    }

    // 送れていない記録を送ってから、ほかの Mac が書いた記録を取ってくる
    func sync() {
        guard let client = settings.makeSyncClient() else { return }
        guard !isSyncing else {
            syncAgain = true
            return
        }
        isSyncing = true
        Task {
            defer { isSyncing = false }
            do {
                repeat {
                    syncAgain = false
                    let rows = ledger.rows(from: state.events)
                    for start in stride(from: 0, to: rows.count, by: SyncClient.maxRowsPerPush) {
                        let batch = Array(rows[start..<min(start + SyncClient.maxRowsPerPush, rows.count)])
                        try await client.pushActivity(batch)
                        ledger.didPush(batch)
                        save()
                    }
                    var hasMore = true
                    while hasMore {
                        let page = try await client.pullActivity(since: ledger.cursor)
                        state.events = ActivitySync.merge(state.events, with: page.events)
                        ledger.cursor = page.cursor
                        hasMore = page.hasMore
                        save()
                    }
                } while syncAgain
            } catch {
                // 送れなかった記録は pending に残るので、次の同期で送り直す
            }
        }
    }

    private func save() {
        JSONFile<[ActivityEvent]>(AppPaths.activity).save(state.events)
        JSONFile<ActivityLedger>(AppPaths.activitySync).save(ledger)
    }
}
