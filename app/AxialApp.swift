import AppKit

@main enum AxialApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AxialAppDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) {app.run()}
    }
}
