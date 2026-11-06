import SwiftUI

@main
struct WinMixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandMenu("Audio") {
                Button(action: {
                    appDelegate.model?.toggleAntiDucking()
                }) {
                    Text(appDelegate.model?.isAntiDuckingEnabled == true ? "✓ 🛡️ Anti-Ducking (Aktif)" : "🛡️ Anti-Ducking (Nonaktif)")
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
    }
}

