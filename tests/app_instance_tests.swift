import Foundation
import Darwin

@main enum AppInstanceTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("axial-instance-" + UUID().uuidString)
        defer {try? FileManager.default.removeItem(at: directory)}
        let first = AppInstance(), second = AppInstance()
        let acquired = try first.claim(directory: directory.path);precondition(acquired)
        precondition(first.ownsLock)
        let duplicate = try second.claim(directory: directory.path);precondition(!duplicate)
        precondition(!second.ownsLock)
        first.release()
        let reclaimed = try second.claim(directory: directory.path);precondition(reclaimed)
        second.release()
        let lock = directory.appendingPathComponent("app.lock")
        try FileManager.default.removeItem(at: lock)
        try FileManager.default.createSymbolicLink(at: lock, withDestinationURL: directory.appendingPathComponent("foreign"))
        do {_ = try first.claim(directory: directory.path);fatalError("Accepted symlink lock")} catch {}
        precondition(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("foreign").path))
        print("PASS: exclusive app ownership, relaunch contention, lock release and symlink rejection")
    }
}
