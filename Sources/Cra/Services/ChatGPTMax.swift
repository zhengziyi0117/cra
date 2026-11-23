import CryptoKit
import Foundation
import Observation
import Security

/// The provider choice belongs to this Mac and data directory, alongside its encrypted DevKit session.
@MainActor @Observable
final class ChatGPTMax {
    static let shared = ChatGPTMax()
    private(set) var selected = false
    private(set) var connected = false
    private(set) var account: String?
    private(set) var model: String?
    enum ConnectionAction: String { case status, connect, disconnect }
    private(set) var pending: ConnectionAction?
    private(set) var error: String?
    var available: Bool { selected && model != nil }

    @ObservationIgnored private var directory: URL?
    @ObservationIgnored private var invalidate: () -> Void = {}
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var epoch = UUID()
    private var selectionFile: URL? { directory?.appendingPathComponent("use-chatgpt") }

    func configure(directory: URL, invalidate: @escaping () -> Void) {
        self.directory = directory
        self.invalidate = invalidate
        selected = selectionFile.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        if selected { refresh() }
    }

    func select(_ cloud: Bool) {
        guard cloud != selected, let directory, let selectionFile else { return }
        do {
            if cloud {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                       attributes: [.posixPermissions: 0o700])
                try Data().write(to: selectionFile, options: .atomic)
            } else {
                try FileManager.default.removeItem(at: selectionFile)
            }
        } catch { self.error = "Cra couldn’t save the Max provider choice."; return }
        epoch = UUID()
        operation?.cancel()
        selected = cloud
        model = nil
        account = nil
        connected = false
        error = nil
        pending = nil
        invalidate()
        if cloud { refresh() }
    }

    func refresh() {
        guard let directory, FileManager.default.fileExists(atPath: directory.appendingPathComponent("chatgpt-auth.json").path)
        else { return }
        changeConnection(.status)
    }

    func changeConnection(_ action: ConnectionAction) {
        guard selected, pending == nil, let directory else { return }
        epoch = UUID()
        let token = epoch
        let previouslyAvailable = available
        model = nil
        pending = action
        error = nil
        if previouslyAvailable { invalidate() }
        operation = Task {
            do {
                let reply = try await ChatGPTHelper.call(command: action.rawValue, directory: directory)
                guard token == epoch else { return }
                connected = reply.connected ?? (reply.code == "revocation_failed" ? false : connected)
                account = connected ? reply.account ?? account : nil
                model = connected ? reply.model : nil
                error = reply.error
            } catch {
                guard token == epoch else { return }
                self.error = error is CancellationError ? nil : error.localizedDescription
            }
            pending = nil
            operation = nil
        }
    }

    func cancelConnection() {
        operation?.cancel()
    }

    func answer<T: Decodable>(_ instructions: String, prompt: String, shape: String,
                              history: [ChatGPTHelper.Message] = []) async throws -> T {
        guard let directory, selected, let model else { throw ChatGPTHelper.Failure("Connect ChatGPT in Max settings.") }
        let token = epoch
        let reply = try await ChatGPTHelper.call(command: "answer", directory: directory, model: model,
            instructions: instructions + "\nReturn only a JSON object, without a code fence. Use this shape: " + shape,
            messages: history + [.init(role: "user", content: prompt)])
        try Task.checkCancellation()
        guard token == epoch else { throw CancellationError() }
        if let message = reply.error {
            error = message
            if ["sign_in_required", "sharing_not_enabled", "invalid_grant", "invalid_refresh_token",
                "token_expired", "refresh_token_expired", "refresh_token_invalidated", "refresh_token_reused"].contains(reply.code) {
                self.model = nil
                invalidate()
            }
            throw ChatGPTHelper.Failure(message)
        }
        guard let text = reply.text else { throw ChatGPTHelper.Failure("ChatGPT returned an empty response.") }
        return try JSONDecoder().decode(T.self, from: Data(text.utf8))
    }
}

enum ChatGPTHelper {
    struct Message: Encodable { let role: String; let content: String }
    struct Reply: Decodable {
        let connected: Bool?
        let account: String?
        let model: String?
        let text: String?
        let error: String?
        let code: String?
    }
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
    private struct Request: Encodable {
        let command: String
        let directory: String
        let key: Data
        let model: String?
        let instructions: String?
        let messages: [Message]
    }

    static func call(command: String, directory: URL, model: String? = nil, instructions: String? = nil,
                     messages: [Message] = []) async throws -> Reply {
        guard let node = Bundle.main.url(forAuxiliaryExecutable: "CraMaxNode"),
              let script = Bundle.main.url(forResource: "helper", withExtension: "cjs", subdirectory: "chatgpt")
        else { throw Failure("The ChatGPT helper is missing from this copy of Cra.") }
        let key = try storageKey(for: directory)
        let payload = try JSONEncoder().encode(Request(command: command, directory: directory.path, key: key,
                                                      model: model, instructions: instructions, messages: messages))
        return try await exchange(node: node, script: script, payload: payload)
    }

    static func exchange(node: URL, script: URL, payload: Data) async throws -> Reply {
        try Task.checkCancellation()
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = node
        process.arguments = ["--no-addons", "--no-global-search-paths", script.path]
        process.currentDirectoryURL = script.deletingLastPathComponent()
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        // EOF tells the DevKit to abort. Let a refresh that already rotated its token finish persisting.
        let writer = input.fileHandleForWriting
        _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
        return try await withTaskCancellationHandler {
            defer { try? writer.close() }
            try Task.checkCancellation()
            let data: Data = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: Result {
                        try writer.write(contentsOf: payload + [0x0a])
                        return try output.fileHandleForReading.readToEnd() ?? Data()
                    })
                }
            }
            try Task.checkCancellation()
            guard !data.isEmpty else { throw Failure("The ChatGPT helper stopped before replying.") }
            return try JSONDecoder().decode(Reply.self, from: data)
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }

    private static func storageKey(for directory: URL) throws -> Data {
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Cra Max ChatGPT", kSecAttrAccount as String: directory.standardizedFileURL.path]
        var query = item
        query[kSecReturnData as String] = true
        var value: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &value)
        if status == errSecSuccess, let data = value as? Data, data.count == 32 { return data }
        guard status == errSecItemNotFound else { throw Failure("Cra couldn’t read the ChatGPT key in your Keychain.") }
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        var entry = item
        entry[kSecValueData as String] = key
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(entry as CFDictionary, nil)
        if added == errSecDuplicateItem { return try storageKey(for: directory) }
        guard added == errSecSuccess else { throw Failure("Cra couldn’t save the ChatGPT key in your Keychain.") }
        return key
    }
}
