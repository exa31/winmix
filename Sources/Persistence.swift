import Foundation

/// Persists volume, mute, output preferences, and themes in UserDefaults.
enum Persistence {
    private static let d = UserDefaults.standard

    private static func gainKey(_ b: String) -> String { "wvm.gain.\(b)" }
    private static func muteKey(_ b: String) -> String { "wvm.mute.\(b)" }
    private static func outputKey(_ b: String) -> String { "wvm.out.\(b)" }

    static func gain(for bundleID: String) -> Float {
        if let v = d.object(forKey: gainKey(bundleID)) as? Double {
            return min(1.0, max(0.0, Float(v)))
        }
        return 1.0
    }

    static func setGain(_ g: Float, for bundleID: String) {
        let clamped = min(1.0, max(0.0, g))
        d.set(Double(clamped), forKey: gainKey(bundleID))
    }

    static func mute(for bundleID: String) -> Bool {
        d.bool(forKey: muteKey(bundleID))
    }

    static func setMute(_ m: Bool, for bundleID: String) {
        d.set(m, forKey: muteKey(bundleID))
    }

    static func appOutputUID(for bundleID: String) -> String? {
        d.string(forKey: outputKey(bundleID))
    }

    static func setAppOutputUID(_ uid: String?, for bundleID: String) {
        if let uid = uid {
            d.set(uid, forKey: outputKey(bundleID))
        } else {
            d.removeObject(forKey: outputKey(bundleID))
        }
    }

    static var masterGain: Float {
        get { (d.object(forKey: "wvm.master.gain") as? Double).map(Float.init) ?? 1.0 }
        set { d.set(Double(newValue), forKey: "wvm.master.gain") }
    }

    static var masterMute: Bool {
        get { d.bool(forKey: "wvm.master.mute") }
        set { d.set(newValue, forKey: "wvm.master.mute") }
    }

    static var preferredOutputUID: String? {
        get { d.string(forKey: "wvm.output.uid") }
        set { d.set(newValue, forKey: "wvm.output.uid") }
    }

    /// Auto-follow system default output device (true by default)
    static var isAutoOutputFollowing: Bool {
        get {
            if let val = d.object(forKey: "wvm.output.auto") as? Bool {
                return val
            }
            return true // Default: auto follow macOS system output
        }
        set { d.set(newValue, forKey: "wvm.output.auto") }
    }

    static var manualOutputUID: String? {
        get { d.string(forKey: "wvm.output.manualUID") }
        set { d.set(newValue, forKey: "wvm.output.manualUID") }
    }

    static var isWindowsClassicTheme: Bool {
        get { d.bool(forKey: "wvm.theme.classic") }
        set { d.set(newValue, forKey: "wvm.theme.classic") }
    }

    /// Exclude our own bundle so we never tap ourselves
    static var excludedBundleIDs: Set<String> {
        var set: Set<String> = [
            "io.github.winmix",
            "com.antigravity.WindowsVolumeMixer",
            "com.apple.controlcenter"
        ]
        if let currentID = Bundle.main.bundleIdentifier {
            set.insert(currentID)
        }
        return set
    }
}

