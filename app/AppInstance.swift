import Foundation
import Darwin

/// A per-user kernel lock also covers explicit launches of different build copies.
/// Notifications only request a window; they never start the input service.
final class AppInstance {
    static let showSettings = Notification.Name("pro.jest.Axial.showSettings")
    static var user: String {String(getuid())}
    private var descriptor: Int32 = -1
    private(set) var ownsLock = false
    func claim(directory: String = "/tmp/axial-\(getuid())") throws -> Bool {
        if ownsLock {return true}
        var info = stat()
        if lstat(directory, &info) != 0 {
            guard errno == ENOENT, mkdir(directory, 0o700) == 0 || errno == EEXIST,
                  lstat(directory, &info) == 0 else {throw POSIXError(.EACCES)}
        }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), info.st_uid == getuid(), info.st_mode & 0o077 == 0 else {throw POSIXError(.EACCES)}
        let fd = open(directory + "/app.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else {throw POSIXError(.EACCES)}
        guard fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_uid == getuid(), info.st_nlink == 1, info.st_mode & 0o077 == 0 else {close(fd);throw POSIXError(.EACCES)}
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let busy = errno == EWOULDBLOCK;close(fd)
            if busy {return false}
            throw POSIXError(.EIO)
        }
        descriptor = fd;ownsLock = true;return true
    }
    func release() {if descriptor >= 0 {close(descriptor);descriptor = -1};ownsLock = false}
    deinit {release()}
}
