import CoreImage
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
                PhoneSetupRow()
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

// スマホの Web アプリを開く QR コード。URL の # の後ろに合言葉を付ける。# の後ろはサーバーに送られない。
// 合言葉が画面に出るので、押したときだけ出す
private struct PhoneSetupRow: View {
    @Environment(SettingsStore.self) private var settings
    @State private var isShown = false

    var body: some View {
        HStack {
            Text("Open Gloss on your phone").foregroundStyle(.secondary)
            Spacer()
            Button("Show QR Code") { isShown = true }
                .disabled(settings.state.syncURL.isEmpty)
                .popover(isPresented: $isShown) {
                    PhoneQRCode(url: settings.state.syncURL)
                }
        }
        .font(.callout)
    }
}

private struct PhoneQRCode: View {
    let url: String

    var body: some View {
        VStack(spacing: 12) {
            if let token = Keychain.apiKey(service: SyncClient.keychainService),
               let image = Self.qrCode(for: Self.base(url) + "/#token=" + token) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
                Text("Scan with your phone's camera, then add it to your Home Screen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 220)
            } else {
                Text("Save the sync token first.").foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    static func base(_ url: String) -> String {
        var base = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        return base
    }

    static func qrCode(for text: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
