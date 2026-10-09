import GlossCore
import SwiftUI

// 入力したキーは Keychain に保存する。保存済みのキーは画面に出さない
struct APIKeyField: View {
    let service: String
    @State private var draft = ""
    @State private var isSaved = false
    @State private var failed = false

    var body: some View {
        LabeledContent("API キー") {
            HStack(spacing: 8) {
                SecureField("API キー", text: $draft, prompt: Text(isSaved ? "保存済み(変えるときだけ入力)" : "貼り付けて保存"))
                    .labelsHidden()
                    .onSubmit(save)
                Button("保存", action: save)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .task { isSaved = Keychain.hasKey(service: service) }
        if failed {
            Text(failureMessage)
                .font(.caption)
                .foregroundStyle(.red)
        } else {
            Text(isSaved ? "Keychain に保存済み(\(service))" : "未登録(\(service))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var failureMessage: String {
        Keychain.isAcceptableKey(draft) || draft.isEmpty
            ? "Keychain に保存できませんでした"
            : "改行などの制御文字を含むキーは保存できません"
    }

    private func save() {
        failed = !Keychain.setAPIKey(draft, service: service)
        if !failed { draft = "" }
        isSaved = Keychain.hasKey(service: service)
    }
}
