import SwiftUI
import AppKit
import CoreAudio

/// Bridges the real-time engine to SwiftUI on the main actor.
@MainActor
final class MixerModel: ObservableObject {

    struct Channel: Identifiable {
        let id: AudioObjectID
        let slot: Int
        let bundleID: String
        let name: String
        let iconPath: String?
        var outputUID: String?
        var gain: Float
        var muted: Bool
    }

    struct Meter {
        var level: Float = 0
        var peak: Float = 0
    }

    struct OutputDevice: Identifiable, Hashable {
        let id: AudioObjectID
        let name: String
        let uid: String
    }

    @Published private(set) var channels: [Channel] = []
    @Published private(set) var levels: [AudioObjectID: Meter] = [:]
    @Published private(set) var masterMeter = Meter()
    @Published private(set) var state: EngineState = .idle
    @Published private(set) var outputName: String = "Speakers"
    @Published private(set) var isAutoOutput: Bool = Persistence.isAutoOutputFollowing
    @Published var masterGain: Float
    @Published var masterMute: Bool
    @Published var isClassicTheme: Bool {
        didSet { Persistence.isWindowsClassicTheme = isClassicTheme }
    }
    @Published private(set) var hasAttempted: Bool

    let engine = TapEngine()
    private var meterTimer: Timer?
    private var iconCache: [String: NSImage] = [:]

    init() {
        masterGain = Persistence.masterGain
        masterMute = Persistence.masterMute
        isClassicTheme = Persistence.isWindowsClassicTheme
        hasAttempted = UserDefaults.standard.bool(forKey: "wvm.hasAttempted")

        engine.onUpdate = { [weak self] snap in
            Task { @MainActor in self?.apply(snap) }
        }
    }

    var needsPrimer: Bool {
        if case .permissionNeeded = state { return true }
        return !hasAttempted
    }

    func startEngine() {
        hasAttempted = true
        UserDefaults.standard.set(true, forKey: "wvm.hasAttempted")
        engine.setMasterGain(masterGain)
        engine.setMasterMute(masterMute)
        engine.start()
        startMeterTimer()
    }

    private func apply(_ snap: EngineSnapshot) {
        state = snap.state
        outputName = snap.outputDeviceName
        let newChannels = snap.channels.map { ec in
            Channel(id: ec.process.objectID,
                    slot: ec.slot,
                    bundleID: ec.identity.bundleID,
                    name: ec.identity.name,
                    iconPath: ec.identity.iconPath,
                    outputUID: ec.outputUID,
                    gain: Persistence.gain(for: ec.identity.bundleID),
                    muted: Persistence.mute(for: ec.identity.bundleID))
        }
        channels = newChannels
        let ids = Set(newChannels.map { $0.id })
        levels = levels.filter { ids.contains($0.key) }
    }

    // MARK: - Live Volume & Mute Controls

    func setGain(_ g: Float, id: AudioObjectID) {
        guard let idx = channels.firstIndex(where: { $0.id == id }) else { return }
        channels[idx].gain = g
        engine.setGain(g, slot: channels[idx].slot)
        Persistence.setGain(g, for: channels[idx].bundleID)
    }

    func setAppOutput(uid: String?, id: AudioObjectID) {
        guard let idx = channels.firstIndex(where: { $0.id == id }) else { return }
        channels[idx].outputUID = uid
        engine.setAppOutput(uid: uid, slot: channels[idx].slot, bundleID: channels[idx].bundleID)
    }

    func toggleMute(id: AudioObjectID) {
        guard let idx = channels.firstIndex(where: { $0.id == id }) else { return }
        let m = !channels[idx].muted
        channels[idx].muted = m
        engine.setMute(m, slot: channels[idx].slot)
        Persistence.setMute(m, for: channels[idx].bundleID)
    }

    func setMasterGain(_ g: Float) {
        masterGain = g
        engine.setMasterGain(g)
        Persistence.masterGain = g
    }

    func toggleMasterMute() {
        masterMute.toggle()
        engine.setMasterMute(masterMute)
        Persistence.masterMute = masterMute
    }

    // MARK: - Output Devices

    func outputDevices() -> [OutputDevice] {
        HAL.outputDevices().compactMap { dev in
            guard let name = HAL.deviceName(dev), let uid = HAL.deviceUID(dev) else { return nil }
            return OutputDevice(id: dev, name: name, uid: uid)
        }
    }

    func selectOutputAuto() {
        isAutoOutput = true
        engine.setAutoOutput()
    }

    func selectOutput(_ id: AudioObjectID) {
        isAutoOutput = false
        engine.setManualOutput(devID: id)
    }

    // MARK: - Real-time VU Meters (40 Hz)

    private func startMeterTimer() {
        meterTimer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 40.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickMeters() }
        }
        RunLoop.main.add(t, forMode: .common)
        meterTimer = t
    }

    private func tickMeters() {
        guard !channels.isEmpty else {
            if !levels.isEmpty { levels = [:] }
            masterMeter = Meter()
            return
        }

        var next: [AudioObjectID: Meter] = [:]
        next.reserveCapacity(channels.count)
        var maxOverallPeak: Float = 0.0

        for ch in channels {
            let (l, r) = engine.peaks(slot: ch.slot)
            let peakVal = max(l, r)
            if peakVal > maxOverallPeak { maxOverallPeak = peakVal }

            let raw = Self.dbScale(peakVal)
            var m = levels[ch.id] ?? Meter()
            m.level = raw > m.level ? raw : m.level * 0.82
            m.peak  = raw > m.peak  ? raw : max(m.peak - 0.015, m.level)
            next[ch.id] = m
        }
        levels = next

        // Master level follows peak of all active audio streams
        let masterRaw = Self.dbScale(maxOverallPeak * (masterMute ? 0 : masterGain))
        var mm = masterMeter
        mm.level = masterRaw > mm.level ? masterRaw : mm.level * 0.82
        mm.peak = masterRaw > mm.peak ? masterRaw : max(mm.peak - 0.015, mm.level)
        masterMeter = mm
    }

    private static func dbScale(_ peak: Float) -> Float {
        guard peak > 0.0001 else { return 0 }
        let db = 20 * log10f(min(peak, 1.5))
        // 0 dBFS maps to ~0.85, up to +3dB headroom
        return max(0, min(1, 1 + db / 50))
    }

    // MARK: - App Icons

    func icon(for channel: Channel) -> NSImage {
        if let cached = iconCache[channel.bundleID] { return cached }
        let image: NSImage
        if let path = channel.iconPath {
            image = NSWorkspace.shared.icon(forFile: path)
        } else {
            image = NSImage(systemSymbolName: "speaker.wave.2.bubble.left.fill", accessibilityDescription: nil)
                ?? NSImage()
        }
        iconCache[channel.bundleID] = image
        return image
    }
}

