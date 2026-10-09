import GlossCore
import SwiftUI

struct SettingsPage: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Form {
            Picker("翻訳エンジン", selection: Binding(get: { settings.state.engine }, set: settings.setEngine)) {
                ForEach(Engine.allCases) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            TextField("モデル", text: Binding(get: { settings.state.model }, set: settings.setModel))
            if settings.state.engine == .jai {
                TextField("ユーザーID", text: Binding(get: { settings.state.jaiUserID }, set: settings.setJAIUserID), prompt: Text("会社のメールアドレス"))
            }
            APIKeyField(service: settings.state.engine.keychainService)
                .id(settings.state.engine)
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}
