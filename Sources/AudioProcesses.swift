import CoreAudio
import Foundation
import AppKit

/// A Core Audio process object plus identifiers.
struct AudioProcess: Identifiable, Hashable {
    let objectID: AudioObjectID
    let pid: pid_t
    let bundleID: String?
    var id: AudioObjectID { objectID }
}

enum AudioProcesses {
    /// Every process object currently recognized by Core Audio HAL.
    static func all() -> [AudioProcess] {
        HAL.list(HAL.system, kAudioHardwarePropertyProcessObjectList, of: AudioObjectID.self).map { oid in
            AudioProcess(objectID: oid,
                         pid: HAL.pid(oid) ?? -1,
                         bundleID: HAL.cfString(oid, kAudioProcessPropertyBundleID))
        }
    }

    /// True when the process has registered active output stream IO.
    static func isRunningOutput(_ oid: AudioObjectID) -> Bool {
        (HAL.uint32(oid, kAudioProcessPropertyIsRunningOutput) ?? 0) != 0
    }

    /// True when the process has registered active input stream IO (microphone/recording/call).
    static func isRunningInput(_ oid: AudioObjectID) -> Bool {
        let sel = AudioObjectPropertySelector(
            (UInt32(UInt8(ascii: "r")) << 24) |
            (UInt32(UInt8(ascii: "i")) << 16) |
            (UInt32(UInt8(ascii: "n")) << 8)  |
             UInt32(UInt8(ascii: "p"))
        )
        return (HAL.uint32(oid, sel) ?? 0) != 0
    }
}

/// Human-facing app name and icon resolution.
struct AppIdentity: Equatable {
    let bundleID: String
    let name: String
    let iconPath: String?

    static func resolve(bundleID: String?, pid: pid_t) -> AppIdentity {
        let bid = bundleID ?? "pid.\(pid)"

        // 1. Try currently running NSRunningApplication
        if pid > 0, let running = NSRunningApplication(processIdentifier: pid) {
            let name = friendlyName(forBundleID: bundleID)
                ?? running.localizedName
                ?? bundleID.map(Self.lastComponent) ?? "Process \(pid)"
            return AppIdentity(bundleID: bid, name: name, iconPath: running.bundleURL?.path)
        }

        // 2. Try looking up workspace app by bundle ID
        if let bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = friendlyName(forBundleID: bundleID)
                ?? FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            return AppIdentity(bundleID: bid, name: name, iconPath: url.path)
        }

        let name = friendlyName(forBundleID: bundleID) ?? bundleID.map(Self.lastComponent) ?? "Process \(pid)"
        return AppIdentity(bundleID: bid, name: name, iconPath: nil)
    }

    private static func lastComponent(_ bundleID: String) -> String {
        let parts = bundleID.split(separator: ".")
        guard let last = parts.last else { return bundleID }
        return last.prefix(1).uppercased() + last.dropFirst()
    }

    /// Common audio-producing helper processes with friendly display names.
    private static func friendlyName(forBundleID bundleID: String?) -> String? {
        guard let bundleID else { return nil }
        switch bundleID {
        case "com.apple.WebKit.GPU",
             "com.apple.Safari":
            return "Safari"
        case "com.google.Chrome",
             "com.google.Chrome.helper",
             "com.google.Chrome.helper.plugin":
            return "Google Chrome"
        case "com.brave.Browser",
             "com.brave.Browser.helper":
            return "Brave Browser"
        case "org.mozilla.firefox",
             "org.mozilla.plugincontainer":
            return "Firefox"
        case "com.microsoft.edgemac",
             "com.microsoft.edgemac.helper":
            return "Microsoft Edge"
        case "net.whatsapp.WhatsApp":
            return "WhatsApp"
        case "com.apple.audio.SystemSoundServer",
             "systemsoundserverd":
            return "System Sounds"
        case "com.apple.avconferenced":
            return "FaceTime / Calls"
        case "com.spotify.client":
            return "Spotify"
        case "com.apple.Music":
            return "Apple Music"
        case "com.apple.QuickTimePlayerX":
            return "QuickTime Player"
        default:
            return nil
        }
    }
}

