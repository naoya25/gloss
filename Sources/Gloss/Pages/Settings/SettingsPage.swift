import GlossCore
import SwiftUI

struct SettingsPage: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(WordsStore.self) private var words

    var body: some View {
        Form {
            Picker("Engine", selection: Binding(get: { settings.state.engine }, set: settings.setEngine)) {
                ForEach(Engine.allCases) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            TextField("Model", text: Binding(get: { settings.state.model }, set: settings.setModel))
            if settings.state.engine == .jai {
                TextField("User ID", text: Binding(get: { settings.state.jaiUserID }, set: settings.setJAIUserID), prompt: Text("Work email"))
            }
            APIKeyField(service: settings.state.engine.keychainService)
                .id(settings.state.engine)

            Section("Book Sync (Cloudflare)") {
                TextField("URL", text: Binding(get: { settings.state.syncURL }, set: settings.setSyncURL), prompt: Text("https://gloss-sync.example.workers.dev"))
                    .onSubmit(words.sync)
                APIKeyField(service: SyncClient.keychainService, label: "Token", onSave: words.sync)
                SyncStatusRow()
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}

private struct SyncStatusRow: View {
    @Environment(WordsStore.self) private var words

    var body: some View {
        HStack {
            switch words.state.sync {
            case .off:
                Text("Enter a URL and token to sync.").foregroundStyle(.secondary)
            case .syncing:
                ProgressView().controlSize(.small)
                Text("Syncing").foregroundStyle(.secondary)
            case .synced(let date):
                Label("Synced at \(date.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.icloud")
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.icloud")
                    .foregroundStyle(.red)
            }
            Spacer()
            Button("Sync Now", action: words.sync)
                .disabled(words.state.sync == .syncing)
        }
        .font(.callout)
    }
}
