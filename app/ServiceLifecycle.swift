import Foundation

@MainActor protocol ServiceLaunching: AnyObject {
    var isRunning: Bool {get}
    func start() throws
    func terminate()
}

// The menu-bar app owns the native helper. Login starts the app, so quitting
// can stop the helper without launchd immediately bringing it back.
@MainActor final class NativeServiceLauncher: ServiceLaunching {
    private var process: Process?
    var isRunning: Bool {process?.isRunning == true}
    func start() throws {
        guard !isRunning else {return}
        let child = Process()
        child.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/Helpers/Axial Service.app/Contents/MacOS/axial-service")
        child.arguments = ["--app-owned"]
        try child.run();process = child
    }
    func terminate() {if let process, process.isRunning {process.terminate()}}
}
