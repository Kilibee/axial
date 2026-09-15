import Foundation

@main enum SessionLogTests {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("axial-log-\(UUID().uuidString)")
        defer {try? FileManager.default.removeItem(at: directory)}
        let log = try SessionLog(directory: directory)
        precondition(log.append(Data("first\n".utf8)));precondition(log.append(Data("second\n".utf8)))
        let destination = directory.appendingPathComponent("export.csv")
        try await log.export(to: destination)
        let expected = "time,device,button,state,reason,device_name,button_name\nfirst\nsecond\n"
        let first = try String(contentsOf: destination);precondition(first == expected)
        precondition(log.append(Data("third\n".utf8)))
        try await log.export(to: destination)
        let second = try String(contentsOf: destination);precondition(second == expected + "third\n")
        let entered = DispatchSemaphore(value: 0), unblock = DispatchSemaphore(value: 0)
        let blocked = SessionLog(url: destination, maxPendingBytes: 8, write: {_ in entered.signal();unblock.wait()})
        precondition(blocked.append(Data(repeating: 1, count: 8)))
        precondition(entered.wait(timeout: .now() + 2) == .success)
        precondition(!blocked.append(Data([2])) && blocked.error != nil)
        unblock.signal();blocked.flush()
        precondition(!blocked.append(Data([3])), "Overflow must be explicit and stop recording")
        let failed = SessionLog(url: destination, maxPendingBytes: 8, write: {_ in throw CocoaError(.fileWriteOutOfSpace)})
        precondition(failed.append(Data([1])));failed.flush()
        precondition(failed.error != nil && !failed.append(Data([2])))
        weak var released: SessionLog?
        do {let temporary = try SessionLog(directory: directory);released = temporary;temporary.append(Data([1]));temporary.flush()}
        precondition(released == nil, "Log writer retained after draining")
        print("PASS: ordered export, replacement, bounded blocked-disk backlog, I/O errors and writer lifetime")
    }
}
