import AppKit
import SwiftUI

/// Own window creation explicitly so login and session restoration never flash settings.
@MainActor final class AxialAppDelegate: NSObject, NSApplicationDelegate {
    private var model: Model?
    private(set) var settingsWindow: NSWindow?
    private(set) var statusItem: NSStatusItem?
    private var quitting = false
    private var handleRelaunches = false
    private let singleInstance: Bool
    private let instance = AppInstance()
    private var reopenObserver: NSObjectProtocol?
    private let makeModel: @MainActor () -> Model
    init(singleInstance: Bool = true, makeModel: @escaping @MainActor () -> Model = {Model()}) {
        self.singleInstance = singleInstance;self.makeModel = makeModel;super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if singleInstance {
            // Register first so a second launch cannot lose its reopen request
            // while this process is still constructing the menu and model.
            reopenObserver = DistributedNotificationCenter.default().addObserver(forName: AppInstance.showSettings, object: AppInstance.user, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.instance.ownsLock, !self.quitting else {return}
                    self.openSettings(nil)
                }
            }
            do {
                guard try instance.claim() else {
                    DistributedNotificationCenter.default().postNotificationName(AppInstance.showSettings, object: AppInstance.user, userInfo: nil, deliverImmediately: true)
                    NSApp.terminate(nil);return
                }
            } catch {
                let alert = NSAlert();alert.messageText = "Axial could not secure its app session."
                alert.informativeText = "Check permissions on the per-user Axial socket directory, then try again."
                alert.runModal();NSApp.terminate(nil);return
            }
        }
        installMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let icon = NSImage(systemSymbolName: "move.3d", accessibilityDescription: "Axial")?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .semibold))
        icon?.isTemplate = true
        item.button?.image = icon;item.button?.toolTip = "Axial"
        item.button?.setAccessibilityLabel("Axial")
        item.menu = makeStatusMenu();statusItem = item
        model = makeModel()
        Task {@MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            await Task.yield()
            self?.handleRelaunches = true
        }
    }

    @objc func openSettings(_ sender: Any?) {
        guard let model else {return}
        if settingsWindow == nil {
            let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Axial"
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentMinSize = NSSize(width: 1096, height: 788)
            window.contentViewController = SettingsWindowController(rootView: SettingsView().environmentObject(model))
            window.center()
            window.setFrameAutosaveName("AxialSettings")
            settingsWindow = window
        }
        settingsWindow?.deminiaturize(nil)
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        let item = menu.addItem(withTitle: "Open Settings…", action: #selector(openSettings(_:)), keyEquivalent: "")
        item.target = self
        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit Axial", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        return menu
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard handleRelaunches else {return false}
        openSettings(nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {false}

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else {return .terminateNow}
        if !quitting {
            quitting = true
            Task {await model.prepareToQuit();sender.reply(toApplicationShouldTerminate: true)}
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown();instance.release()
        if let reopenObserver {DistributedNotificationCenter.default().removeObserver(reopenObserver)}
    }

    private func installMenu() {
        let menu = NSMenu()
        let appMenu = NSMenu(title: "Axial")
        menu.addItem(withTitle: "Axial", action: nil, keyEquivalent: "").submenu = appMenu
        appMenu.addItem(withTitle: "About Axial", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: "Open Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Axial", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editMenu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = editMenu
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        let windowMenu = NSMenu(title: "Window")
        menu.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
    }
}

@MainActor final class SettingsWindow: NSWindow {
    override func miniaturize(_ sender: Any?) {orderOut(sender)}
}

/// Keep window chrome behind the content, with the tabs below the title-bar safe area.
@MainActor final class SettingsWindowController: NSViewController {
    init<Content: View>(rootView: Content) {
        super.init(nibName: nil, bundle: nil)
        let host = NSHostingController(rootView: rootView)
        addChild(host)
        let surface = NSView()
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 16
            glass.tintColor = AxialAppearance.glassTint
            glass.contentView = surface
            view = glass
        } else {
            let material = NSVisualEffectView()
            material.material = .underWindowBackground
            material.blendingMode = .behindWindow
            material.state = .followsWindowActiveState
            surface.translatesAutoresizingMaskIntoConstraints = false
            material.addSubview(surface)
            NSLayoutConstraint.activate([
                surface.leadingAnchor.constraint(equalTo: material.leadingAnchor),
                surface.trailingAnchor.constraint(equalTo: material.trailingAnchor),
                surface.topAnchor.constraint(equalTo: material.topAnchor),
                surface.bottomAnchor.constraint(equalTo: material.bottomAnchor)
            ])
            view = material
        }
        host.view.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            host.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) {fatalError("Use init(rootView:)")}
}
