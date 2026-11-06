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
                    Text(appDelegate.model?.isAntiDuckingEnabled == true
                        ? "✓ 🛡️ Musik Tetap 100% Saat Call (Bypass Ducking)"
                        : "🔉 Musik Mengecil Saat Call (Standar Mac)")
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            }
        }
    }
}

