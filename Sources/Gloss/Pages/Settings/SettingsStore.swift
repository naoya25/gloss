import GlossCore
import Observation

@MainActor
@Observable
final class SettingsStore {
    private(set) var state: AppSettings {
        didSet { JSONFile<AppSettings>(AppPaths.settings).save(state) }
    }

    init() {
        state = JSONFile<AppSettings>(AppPaths.settings).load()
            ?? AppSettings.importingTraPoP(from: AppPaths.traPoPConfig)
    }

    // エンジンを変えたら、モデルもそのエンジンの既定に戻す
    func setEngine(_ engine: Engine) {
        state.engine = engine
        state.model = engine.defaultModel
    }

    func setModel(_ model: String) {
        state.model = model
    }

    func setJAIUserID(_ userID: String) {
        state.jaiUserID = userID
    }

    func setTarget(_ target: TranslationTarget) {
        state.target = target
    }

    func setCardFace(_ face: CardFace) {
        state.cardFace = face
    }

    func setWordSort(_ order: WordSort) {
        state.wordSort = order
    }

    func setSyncURL(_ url: String) {
        state.syncURL = url
    }

    // 同期先の URL と合言葉がそろっていないときは同期しない
    func makeSyncClient() -> SyncClient? {
        guard !state.syncURL.isEmpty, let token = Keychain.apiKey(service: SyncClient.keychainService) else { return nil }
        return try? SyncClient(baseURL: state.syncURL, token: token)
    }

    func makeClient() -> ChatClient {
        ChatClient(engine: state.engine, model: state.model, userID: state.jaiUserID)
    }
}
