import Foundation

// Disk work is serialized, with a bounded backlog and explicit failure state.
// The full-session export uses a file copy, rather than loading the CSV into RAM.
final class SessionLog: @unchecked Sendable {
    let url: URL
    private let queue = DispatchQueue(label: "pro.jest.button-log", qos: .utility)
    private let lock = NSLock()
    private let write: @Sendable (Data) throws -> Void
    private let synchronize: @Sendable () throws -> Void
    private let maxPendingBytes: Int
    private var pendingBytes = 0
    private var failure: String?
    private var file: FileHandle?
    var error: String? {lock.lock();defer {lock.unlock()};return failure}

    init(directory: URL, maxPendingBytes: Int = 4 * 1024 * 1024) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("buttons-\(UUID().uuidString).csv")
        guard FileManager.default.createFile(atPath: url.path, contents: Data("time,device,button,state,reason,device_name,button_name\n".utf8), attributes: [.posixPermissions: 0o600]) else {throw CocoaError(.fileWriteUnknown)}
        let handle = try FileHandle(forWritingTo: url);try handle.seekToEnd();file = handle
        write = {try handle.write(contentsOf: $0)};synchronize = {try handle.synchronize()}
        self.maxPendingBytes = maxPendingBytes
    }
    // Injectable sink for blocked-disk and failure regression tests.
    init(url: URL, maxPendingBytes: Int, write: @escaping @Sendable (Data) throws -> Void, synchronize: @escaping @Sendable () throws -> Void = {}) {
        self.url = url;self.maxPendingBytes = maxPendingBytes;self.write = write;self.synchronize = synchronize
    }
    @discardableResult func append(_ data: Data) -> Bool {
        lock.lock()
        if failure != nil {lock.unlock();return false}
        guard data.count <= maxPendingBytes - pendingBytes else {
            failure = "Button log disk backlog is full; recording stopped. Visible events remain available."
            lock.unlock();return false
        }
        pendingBytes += data.count;lock.unlock()
        queue.async { [self] in
            do {try write(data)} catch {record(error)}
            lock.lock();pendingBytes -= data.count;lock.unlock()
        }
        return true
    }
    private func record(_ error: Error) {
        lock.lock();if failure == nil {failure = "Could not write button log: \(error.localizedDescription)"};lock.unlock()
    }
    func flush() {queue.sync {do {try synchronize()} catch {record(error)}}}
    func export(to destination: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                let temporary = destination.deletingLastPathComponent().appendingPathComponent(".axial-export-\(UUID().uuidString)")
                defer {try? FileManager.default.removeItem(at: temporary)}
                do {
                    try synchronize()
                    try FileManager.default.copyItem(at: url, to: temporary)
                    if FileManager.default.fileExists(atPath: destination.path) {
                        _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
                    } else {try FileManager.default.moveItem(at: temporary, to: destination)}
                    continuation.resume()
                } catch {continuation.resume(throwing: error)}
            }
        }
    }
    deinit {try? file?.close()}
}
