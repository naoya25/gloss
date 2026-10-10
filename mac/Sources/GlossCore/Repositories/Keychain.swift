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

    // 既にある項目(TraPoP が作ったもの)はアカウント名を合わせて上書きする。
    // アカウント名が違うと別の項目が増えて、読むときに古いキーが返ってしまう
    // security -i は1行を1コマンドとして読むので、途中に改行などがあると残りが別コマンドとして実行される
    public static func isAcceptableKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    @discardableResult
    public static func setAPIKey(_ key: String, service: String) -> Bool {
        guard isAcceptableKey(key) else { return false }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = run(["find-generic-password", "-s", service]).flatMap(account(in:)) ?? "gloss"
        // キーをコマンドライン引数に載せると ps で見えるので、security -i の標準入力で渡す
        let command = "add-generic-password -U -s \(quote(service)) -a \(quote(account)) -w \(quote(trimmed))\n"
        guard run(["-i"], input: command) != nil else { return false }
        return apiKey(service: service) == trimmed
    }

    static func account(in attributes: String) -> String? {
        guard let line = attributes.split(separator: "\n").first(where: { $0.contains("\"acct\"<blob>=") }),
              let start = line.firstIndex(of: "=")
        else { return nil }
        let value = line[line.index(after: start)...].trimmingCharacters(in: .whitespaces)
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return nil }
        return String(value.dropFirst().dropLast())
    }

    static func quote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func run(_ arguments: [String], input: String? = nil) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        let stdin = Pipe()
        if input != nil { process.standardInput = stdin }
        do {
            try process.run()
        } catch {
            return nil
        }
        if let input {
            stdin.fileHandleForWriting.write(Data(input.utf8))
            try? stdin.fileHandleForWriting.close()
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
