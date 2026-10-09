import Foundation

// Security.framework で直接読むと、/usr/bin/security が作った項目には
// アクセス許可ダイアログが毎回出る。TraPoP と同じく security コマンド経由で読む
public enum Keychain {
    public static func apiKey(service: String) -> String? {
        guard let output = run(["find-generic-password", "-s", service, "-w"]) else { return nil }
        let key = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    public static func hasKey(service: String) -> Bool {
        run(["find-generic-password", "-s", service]) != nil
    }

    private static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
