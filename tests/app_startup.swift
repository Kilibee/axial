import AppKit

@main enum AppStartupTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AxialAppDelegate(singleInstance: false, makeModel: {Model(live: false)})
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        precondition(app.activationPolicy() == .accessory, "Axial must not create a Dock icon")
        precondition(delegate.settingsWindow == nil, "Every startup must leave settings hidden")
        precondition(delegate.statusItem?.button?.image != nil, "Menu-bar icon must exist at startup")
        precondition(delegate.statusItem?.button?.image?.isTemplate == true)
        precondition(!delegate.applicationShouldHandleReopen(app, hasVisibleWindows: false))
        precondition(delegate.settingsWindow == nil, "A launch-time reopen event must leave settings hidden")
        let menu = delegate.statusItem?.menu
        let settings = menu?.items.first
        precondition(settings?.title == "Open Settings…")
        precondition(settings?.target === delegate && settings?.action == #selector(AxialAppDelegate.openSettings(_:)))
        let quit = menu?.items.last
        precondition(quit?.title == "Quit Axial" && quit?.target === app && quit?.action == #selector(NSApplication.terminate(_:)))
        precondition(!delegate.applicationShouldTerminateAfterLastWindowClosed(app))
        delegate.openSettings(nil)
        precondition(delegate.settingsWindow?.isVisible == true)
        delegate.settingsWindow?.miniaturize(nil)
        precondition(delegate.settingsWindow?.isVisible == false && delegate.settingsWindow?.isMiniaturized == false,
                     "Minimize must hide settings without making a Dock tile")
        delegate.openSettings(nil);precondition(delegate.settingsWindow?.isVisible == true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        precondition(delegate.applicationShouldHandleReopen(app, hasVisibleWindows: true), "Relaunch must also bring an existing visible window forward")
        delegate.settingsWindow?.close()
        precondition(delegate.settingsWindow?.isVisible == false && delegate.statusItem?.isVisible == true)
        print("PASS: menu-bar icon/menu, no Dock icon, hidden startup, reopen, close and minimize-to-menu-bar")
    }
}
