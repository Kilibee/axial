import AppKit
import Darwin

@main enum AppStartupTests {
    // Optimized Swift preconditions can trap without printing their message.
    // Write each result directly so CI retains the failing check or last action.
    static func report(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {report("FAIL: \(message)");exit(1)}
        report("PASS: \(message)")
    }

    @MainActor static func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 5) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        repeat {
            if condition() {return true}
            // Let the delegate's main-actor task and AppKit events make progress.
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        } while ProcessInfo.processInfo.systemUptime < deadline
        return condition()
    }

    @MainActor static func main() {
        report("Starting AppKit and the app delegate")
        let app = NSApplication.shared
        let delegate = AxialAppDelegate(singleInstance: false, makeModel: {Model(live: false)})
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        check(app.activationPolicy() == .accessory, "Axial must not create a Dock icon")
        check(delegate.settingsWindow == nil, "Every startup must leave settings hidden")
        check(delegate.statusItem?.button?.image != nil, "Menu-bar icon must exist at startup")
        check(delegate.statusItem?.button?.image?.isTemplate == true, "Menu-bar icon must be a template image")
        check(!delegate.applicationShouldHandleReopen(app, hasVisibleWindows: false), "Launch-time reopen must be ignored")
        check(delegate.settingsWindow == nil, "A launch-time reopen event must leave settings hidden")
        let menu = delegate.statusItem?.menu
        let settings = menu?.items.first
        check(settings?.title == "Open Settings…", "Menu must offer Open Settings")
        check(settings?.target === delegate && settings?.action == #selector(AxialAppDelegate.openSettings(_:)), "Open Settings must target the app delegate")
        let quit = menu?.items.last
        check(quit?.title == "Quit Axial" && quit?.target === app && quit?.action == #selector(NSApplication.terminate(_:)), "Quit menu item must terminate the app")
        check(!delegate.applicationShouldTerminateAfterLastWindowClosed(app), "Closing settings must leave the app running")
        report("Opening settings")
        delegate.openSettings(nil)
        check(delegate.settingsWindow?.isVisible == true, "Open Settings must show the window")
        delegate.settingsWindow?.miniaturize(nil)
        check(delegate.settingsWindow?.isVisible == false && delegate.settingsWindow?.isMiniaturized == false,
                     "Minimize must hide settings without making a Dock tile")
        delegate.openSettings(nil)
        check(delegate.settingsWindow?.isVisible == true, "Settings must reopen after minimize")
        // The delegate asynchronously enables relaunch handling after startup.
        // A fixed 200 ms run-loop delay races task scheduling on loaded CI runners.
        check(waitUntil {delegate.applicationShouldHandleReopen(app, hasVisibleWindows: true)},
              "Relaunch must bring an existing visible window forward within 5 seconds")
        check(delegate.settingsWindow?.isVisible == true, "Relaunch must leave settings visible")
        delegate.settingsWindow?.close()
        check(delegate.settingsWindow?.isVisible == false && delegate.statusItem?.isVisible == true,
              "Closing settings must hide the window and retain the menu-bar item")
        print("PASS: menu-bar icon/menu, no Dock icon, hidden startup, reopen, close and minimize-to-menu-bar")
    }
}
