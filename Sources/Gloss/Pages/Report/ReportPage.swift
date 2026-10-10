import AppKit
import GlossCore
import SwiftUI

enum ReportTab: String, CaseIterable, Identifiable {
    case today
    case progress

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: "Today"
        case .progress: "Progress"
        }
    }
}

struct ReportPage: View {
    @Environment(ActivityStore.self) private var activity
    @State private var tab: ReportTab = .today

    var body: some View {
        ScrollView {
            Group {
                switch tab {
                case .today: ReportToday()
                case .progress: ReportProgress()
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $tab) {
                    ForEach(ReportTab.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            ToolbarItem {
                CopyReportMenu()
            }
        }
    }
}

// 押すと画像でコピーし、横の矢印から Markdown でもコピーできる。コピーできたら少しの間だけ印を変える
private struct CopyReportMenu: View {
    @Environment(ActivityStore.self) private var activity
    @State private var copied = false

    var body: some View {
        let report = activity.report()
        Menu {
            Button("Copy as Image") { copyImage(report) }
            Button("Copy as Markdown") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report.markdown(), forType: .string)
                flash()
            }
        } label: {
            Label(copied ? "Copied" : "Copy Report", systemImage: copied ? "checkmark" : "doc.on.clipboard")
        } primaryAction: {
            copyImage(report)
        }
        .help("Copy today's report as an image. Use the arrow for Markdown")
        .disabled(report.isEmpty)
    }

    private func copyImage(_ report: DayReport) {
        if ReportShareCard.copy(report: report, streak: activity.state.events.streak(until: .now)) { flash() }
    }

    private func flash() {
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
