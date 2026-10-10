import GlossCore
import SwiftUI

// 入力したキーは Keychain に保存する。保存済みのキーは画面に出さない
struct APIKeyField: View {
    let service: String
    var label = "API Key"
    var onSave: () -> Void = {}
    @State private var draft = ""
    @State private var isSaved = false
    @State private var failed = false

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 8) {
                SecureField(label, text: $draft, prompt: Text(isSaved ? "Saved (enter only to change it)" : "Paste and save"))
                    .labelsHidden()
                    .onSubmit(save)
                Button("Save", action: save)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .task { isSaved = Keychain.hasKey(service: service) }
        if failed {
            Text(failureMessage)
                .font(.caption)
                .foregroundStyle(.red)
        } else {
            Text(isSaved ? "Saved in Keychain (\(service))" : "Not set (\(service))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var failureMessage: String {
        Keychain.isAcceptableKey(draft) || draft.isEmpty
            ? "Couldn't save to Keychain"
            : "Keys with control characters such as line breaks can't be saved"
    }

    private func save() {
        failed = !Keychain.setAPIKey(draft, service: service)
        if !failed { draft = "" }
        isSaved = Keychain.hasKey(service: service)
        if !failed { onSave() }
    }
}
