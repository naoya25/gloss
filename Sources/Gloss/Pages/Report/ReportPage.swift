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
                let report = activity.report()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.markdown(), forType: .string)
                } label: {
                    Label("Copy as Markdown", systemImage: "doc.on.clipboard")
                }
                .help("Copy today's report as Markdown")
                .disabled(report.isEmpty)
            }
        }
    }
}
