import Foundation

@main struct ChatGPTMaxTests {
    @MainActor static func main() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cloud = ChatGPTMax()
        var changes = 0
        cloud.configure(directory: folder) { changes += 1 }
        precondition(!cloud.selected && !cloud.available)
        cloud.select(true)
        precondition(cloud.selected && !cloud.available && changes == 1)
        let restored = ChatGPTMax()
        restored.configure(directory: folder) {}
        precondition(restored.selected && !restored.available)

        let app = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Contents")
        let node = app.appendingPathComponent("MacOS/CraMaxNode")
        let helper = app.appendingPathComponent("Resources/chatgpt/helper.cjs")
        let request: [String: String] = ["command": "status", "directory": folder.path,
                                         "key": Data(repeating: 9, count: 32).base64EncodedString()]
        let reply = try await ChatGPTHelper.exchange(node: node, script: helper,
                                                     payload: JSONEncoder().encode(request))
        precondition(reply.connected == false && reply.error == nil)

        let waiting = folder.appendingPathComponent("wait.cjs")
        try "process.stdin.resume(); setTimeout(() => {}, 30000);".write(to: waiting, atomically: true, encoding: .utf8)
        let task = Task { try await ChatGPTHelper.exchange(node: node, script: waiting, payload: Data()) }
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        do { _ = try await task.value; fatalError("Cancelled helper returned a reply") }
        catch is CancellationError {}

        cloud.select(false)
        precondition(!cloud.selected && changes == 2)
        let nextLaunch = ChatGPTMax()
        nextLaunch.configure(directory: folder) {}
        precondition(!nextLaunch.selected)
        print("ChatGPT Max: local provider choice, disconnected gating, Swift helper transport and cancellation passed.")
    }
}
