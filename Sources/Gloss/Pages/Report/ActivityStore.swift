import Foundation
import GlossCore
import Observation

struct ActivityState {
    var events: [ActivityEvent] = []
}

@MainActor
@Observable
final class ActivityStore {
    static let limit = 20_000

    private(set) var state: ActivityState

    init() {
        state = ActivityState(events: JSONFile<[ActivityEvent]>(AppPaths.activity).load() ?? [])
    }

    func record(_ kind: ActivityKind, title: String, score: Int? = nil, total: Int? = nil, detail: String? = nil) {
        state.events.append(ActivityEvent(kind: kind, title: title, score: score, total: total, detail: detail))
        if state.events.count > Self.limit {
            state.events.removeFirst(state.events.count - Self.limit)
        }
        JSONFile<[ActivityEvent]>(AppPaths.activity).save(state.events)
    }

    func report(on day: Date = .now) -> DayReport {
        DayReport(events: state.events, on: day)
    }
}
