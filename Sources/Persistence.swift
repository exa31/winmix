import Foundation

/// Persists volume, mute, output preferences, and themes in UserDefaults.
enum Persistence {
    private static let d = UserDefaults.standard

    private static func gainKey(_ b: String) -> String { "wvm.gain.\(b)" }
    private static func muteKey(_ b: String) -> String { "wvm.mute.\(b)" }
    private static func outputKey(_ b: String) -> String { "wvm.out.\(b)" }
    private static func devGainKey(_ u: String) -> String { "wvm.dev.gain.\(u)" }
    private static func devMuteKey(_ u: String) -> String { "wvm.dev.mute.\(u)" }

    static func deviceGain(for uid: String) -> Float {
        if let v = d.object(forKey: devGainKey(uid)) as? Double {
            return min(1.0, max(0.0, Float(v)))
        }
        return 1.0
    }

    static func setDeviceGain(_ g: Float, for uid: String) {
        let clamped = min(1.0, max(0.0, g))
        d.set(Double(clamped), forKey: devGainKey(uid))
    }

    static func deviceMute(for uid: String) -> Bool {
        d.bool(forKey: devMuteKey(uid))
    }

    static func setDeviceMute(_ m: Bool, for uid: String) {
        d.set(m, forKey: devMuteKey(uid))
    }

    static func purgeDisconnectedDevice(_ deadUID: String) {
        if manualOutputUID == deadUID {
            manualOutputUID = nil
            isAutoOutputFollowing = true
        }
        let dict = d.dictionaryRepresentation()
        for key in dict.keys where key.hasPrefix("wvm.out.") {
            if let val = dict[key] as? String, val == deadUID {
                d.removeObject(forKey: key)
            }
        }
        d.removeObject(forKey: devGainKey(deadUID))
        d.removeObject(forKey: devMuteKey(deadUID))
    }

    @discardableResult
    static func cleanOrphanedOutputs(validUIDs: Set<String>) -> [String] {
        var cleaned: [String] = []
        if let man = manualOutputUID, !validUIDs.contains(man) {
            manualOutputUID = nil
            isAutoOutputFollowing = true
        }
        let dict = d.dictionaryRepresentation()
        for key in dict.keys where key.hasPrefix("wvm.out.") {
            if let val = dict[key] as? String, !validUIDs.contains(val) {
                d.removeObject(forKey: key)
                let bundle = String(key.dropFirst("wvm.out.".count))
                cleaned.append(bundle)
            }
        }
        return cleaned
    }

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

    /// Anti-ducking (bypasses automatic volume attenuation during WhatsApp/VoIP calls)
    static var isAntiDuckingEnabled: Bool {
        get {
            if let val = d.object(forKey: "wvm.antiduck.enabled") as? Bool {
                return val
            }
            return true // Default: Anti-ducking enabled
        }
        set { d.set(newValue, forKey: "wvm.antiduck.enabled") }
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

