import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    var model: MixerModel!
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Show in Dock as a regular app
        NSApplication.shared.setActivationPolicy(.regular)

        model = MixerModel()
        model.startEngine()

        setupStatusItem()
        setupMainWindow()

        // Ensure window is shown and brought to front on launch
        DispatchQueue.main.async { [weak self] in
            self?.showMainWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.engine.stopSync()
    }

    // MARK: - Menu Bar Status Item & Popover

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: "WinMix")
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }

        popover = NSPopover()
        popover?.contentSize = NSSize(width: 540, height: 360)
        popover?.behavior = .transient
        popover?.delegate = self

        let view = WindowsMixerView(model: model, isStandaloneWindow: false, onDetach: { [weak self] in
            self?.popover?.performClose(nil)
            self?.showMainWindow()
        })
        popover?.contentViewController = NSHostingController(rootView: view)
    }

    @objc func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showContextMenu(sender)
        } else {
            togglePopover()
        }
    }

    private func showContextMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Buka WinMix", action: #selector(openMainWindowAction), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let antiDuckItem = NSMenuItem(
            title: model.isAntiDuckingEnabled
                ? "✓ 🛡️ Musik Tetap 100% Saat Call (Bypass Ducking)"
                : "🔉 Musik Mengecil Saat Call (Standar Mac)",
            action: #selector(toggleAntiDuckAction),
            keyEquivalent: "d"
        )
        antiDuckItem.target = self
        antiDuckItem.state = model.isAntiDuckingEnabled ? .on : .off
        menu.addItem(antiDuckItem)

        let themeItem = NSMenuItem(
            title: model.isClassicTheme ? "Ganti ke Tema Windows 11" : "Ganti ke Tema Classic SndVol",
            action: #selector(toggleThemeAction),
            keyEquivalent: "t"
        )
        themeItem.target = self
        menu.addItem(themeItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Keluar dari WinMix", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        sender.performClick(nil)
        statusItem?.menu = nil
    }

    @objc func openMainWindowAction() {
        showMainWindow()
    }

    @objc func toggleAntiDuckAction() {
        model.toggleAntiDucking()
    }

    @objc func toggleThemeAction() {
        model.isClassicTheme.toggle()
    }

    @objc func quitAction() {
        NSApplication.shared.terminate(nil)
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Standalone Window

    private func setupMainWindow() {
        let view = WindowsMixerView(model: model, isStandaloneWindow: true)
        let hostingController = NSHostingController(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.setFrameAutosaveName("WinMixMainWindow")
        window.title = "WinMix - Volume Mixer"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.delegate = self

        mainWindow = window
        window.makeKeyAndOrderFront(nil)
    }

    func showMainWindow() {
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        } else {
            setupMainWindow()
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        updateUIVisibility()
    }

    func updateUIVisibility() {
        let isWinVisible = mainWindow?.isVisible == true && !(mainWindow?.isMiniaturized == true)
        let isPopVisible = popover?.isShown == true
        model.isUIVisible = isWinVisible || isPopVisible
    }

    // Closing the window with 'X' hides it without destroying state (Dock icon/menu bar restores it)
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        updateUIVisibility()
        return false
    }

    func windowDidMiniaturize(_ notification: Notification) { updateUIVisibility() }
    func windowDidDeminiaturize(_ notification: Notification) { updateUIVisibility() }
    func windowDidBecomeKey(_ notification: Notification) { updateUIVisibility() }
    func windowDidResignKey(_ notification: Notification) { updateUIVisibility() }

    // NSPopoverDelegate
    func popoverDidShow(_ notification: Notification) { updateUIVisibility() }
    func popoverDidClose(_ notification: Notification) { updateUIVisibility() }
}
