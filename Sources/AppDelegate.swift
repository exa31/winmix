import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
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
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover?.contentSize = NSSize(width: 540, height: 360)
        popover?.behavior = .transient

        let view = WindowsMixerView(model: model, isStandaloneWindow: false, onDetach: { [weak self] in
            self?.popover?.performClose(nil)
            self?.showMainWindow()
        })
        popover?.contentViewController = NSHostingController(rootView: view)
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
    }

    // Closing the window with 'X' hides it without destroying state (Dock icon/menu bar restores it)
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
