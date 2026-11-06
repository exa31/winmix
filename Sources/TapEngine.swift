import CoreAudio
import Foundation
import os

/// One tapped, controllable application audio stream.
struct EngineChannel: Identifiable {
    let slot: Int
    let process: AudioProcess
    let identity: AppIdentity
    var outputUID: String?
    var isCallApp: Bool = false
    var isDucked: Bool = false
    var id: AudioObjectID { process.objectID }
}

enum EngineState: Equatable {
    case idle
    case running              // Per-app control active
    case permissionNeeded     // First tap failed -> prompt for audio-capture TCC
    case degraded(String)     // Fail-safe: audio plays straight through without interruption
}

struct EngineSnapshot {
    let state: EngineState
    let channels: [EngineChannel]
    let outputDeviceName: String
    let isCallActive: Bool
    let activeCallAppName: String?
}

/// Manages process taps + Core Audio private aggregate device + real-time IOProc.
///
/// Safety model:
/// - Uses CATapMutedWhenTapped: if this app quits or the audio IO stalls, macOS automatically
///   unmutes tapped apps so normal system playback is never lost.
/// - We never set a virtual driver as default output device.
final class TapEngine {
    private let ctx: OpaquePointer
    private let ioQueue: DispatchQueue
    private let engineQueue = DispatchQueue(label: "io.github.winmix.engine", qos: .userInitiated)

    private var aggregateID: AudioObjectID = 0
    private var ioProcID: AudioDeviceIOProcID?
    private var realOutputDevice: AudioObjectID = 0
    private var realOutputUID: String = ""
    private var realOutputName: String = "Speakers"
    private var activeOutputUIDs: [String] = []
    private(set) var isAutoOutput: Bool = Persistence.isAutoOutputFollowing
    private(set) var manualOutputUID: String? = Persistence.manualOutputUID
    private(set) var isAntiDuckingEnabled: Bool = Persistence.isAntiDuckingEnabled

    private var channels: [EngineChannel] = []
    private var tapsByProcess: [AudioObjectID: (tapID: AudioObjectID, uid: String)] = [:]
    private var lastActive: [AudioObjectID: Date] = [:]
    private var lastCallActive: Bool = false
    private var lastCallAppName: String? = nil
    private var isTestingDucking: Bool = false

    private var running = false
    private var everCreatedTap = false
    private var permissionRetryAt: Date?
    private var activityToken: NSObjectProtocol?
    private var outputListener: ListenerToken?
    private var pollTimer: DispatchSourceTimer?

    private let hysteresis: TimeInterval = 30.0

    var onUpdate: ((EngineSnapshot) -> Void)?

    init() {
        guard let c = rt_context_create() else {
            fatalError("Failed to allocate real-time mixing context")
        }
        ctx = c
        ioQueue = DispatchQueue(label: "io.github.winmix.io", qos: .userInteractive)
    }

    deinit {
        rt_context_destroy(ctx)
    }

    // MARK: - Live Control

    func setGain(_ g: Float, slot: Int) {
        engineQueue.async { [weak self] in
            guard let self = self else { return }
            if let ch = self.channels.first(where: { $0.slot == slot }) {
                Persistence.setGain(g, for: ch.identity.bundleID)
                let eff = self._effectiveGain(for: ch, callActive: self._isCallActive())
                rt_set_gain(self.ctx, Int32(slot), eff)
            } else {
                rt_set_gain(self.ctx, Int32(slot), g)
            }
        }
    }
    func setMute(_ m: Bool, slot: Int)   { rt_set_mute(ctx, Int32(slot), m) }
    func setMasterGain(_ g: Float)       { rt_set_master_gain(ctx, g) }
    func setMasterMute(_ m: Bool)        { rt_set_master_mute(ctx, m) }
    func peaks(slot: Int) -> (Float, Float) {
        (rt_get_peak_l(ctx, Int32(slot)), rt_get_peak_r(ctx, Int32(slot)))
    }
    func cycleCount() -> UInt64 { rt_get_cycles(ctx) }

    // MARK: - Lifecycle

    func start() {
        engineQueue.async { [weak self] in self?._start() }
    }

    func stopSync() {
        engineQueue.sync { [weak self] in self?._teardownAll() }
    }

    private func _start() {
        guard !running else { return }
        running = true

        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Windows Volume Mixer per-app real-time audio routing")

        outputListener = HAL.addListener(HAL.system, kAudioHardwarePropertyDefaultOutputDevice, queue: engineQueue) { [weak self] in
            self?._handleDefaultOutputChanged()
        }

        let t = DispatchSource.makeTimerSource(queue: engineQueue)
        t.schedule(deadline: .now() + 0.2, repeating: 0.4)
        t.setEventHandler { [weak self] in self?._refresh() }
        t.resume()
        pollTimer = t

        _updateRealOutput()
        _refresh()
    }

    private func _updateRealOutput() {
        if isAutoOutput || manualOutputUID == nil {
            guard let dev = HAL.defaultOutputDevice(), let uid = HAL.deviceUID(dev) else { return }
            realOutputDevice = dev
            realOutputUID = uid
            realOutputName = HAL.deviceName(dev) ?? "Speakers"
        } else if let manualUID = manualOutputUID {
            let devs = HAL.outputDevices()
            if let match = devs.first(where: { HAL.deviceUID($0) == manualUID }) {
                realOutputDevice = match
                realOutputUID = manualUID
                realOutputName = HAL.deviceName(match) ?? "Output"
            } else {
                guard let dev = HAL.defaultOutputDevice(), let uid = HAL.deviceUID(dev) else { return }
                realOutputDevice = dev
                realOutputUID = uid
                realOutputName = HAL.deviceName(dev) ?? "Speakers"
            }
        }
    }

    private func _handleDefaultOutputChanged() {
        guard isAutoOutput else { return }
        let old = realOutputUID
        _updateRealOutput()
        guard realOutputUID != old, !realOutputUID.isEmpty else { return }
        log.info("Audio output changed to \(self.realOutputName, privacy: .public)")
        let desired = channels.map { $0.process }
        _rebuildGraph(desired: desired)
    }

    func setAutoOutput() {
        engineQueue.async { [weak self] in
            guard let self = self else { return }
            self.isAutoOutput = true
            self.manualOutputUID = nil
            Persistence.isAutoOutputFollowing = true
            Persistence.manualOutputUID = nil
            self._updateRealOutput()
            let desired = self.channels.map { $0.process }
            self._rebuildGraph(desired: desired)
        }
    }

    func setManualOutput(devID: AudioObjectID) {
        engineQueue.async { [weak self] in
            guard let self = self, let uid = HAL.deviceUID(devID) else { return }
            self.isAutoOutput = false
            self.manualOutputUID = uid
            Persistence.isAutoOutputFollowing = false
            Persistence.manualOutputUID = uid
            self.realOutputDevice = devID
            self.realOutputUID = uid
            self.realOutputName = HAL.deviceName(devID) ?? "Output"
            let desired = self.channels.map { $0.process }
            self._rebuildGraph(desired: desired)
        }
    }

    func setAntiDuckingEnabled(_ enabled: Bool) {
        engineQueue.async { [weak self] in
            guard let self = self else { return }
            self.isAntiDuckingEnabled = enabled
            Persistence.isAntiDuckingEnabled = enabled
            let devices = self._allOutputDeviceIDs()

            if enabled {
                // Smooth fade UP to full volume in 250ms
                for dev in devices {
                    _ = Self.audioDeviceDuck?(dev, 1.0, nil, 0.25)
                }
                self._applyUnduck()
            } else {
                // Smooth fade DOWN back to ducked volume (25%) in 350ms
                for dev in devices {
                    _ = Self.audioDeviceDuck?(dev, 0.25, nil, 0.35)
                }
                self._writeDuckProperty([0.0, 0.0, 0.0, 0.0], devices: devices)
            }
            self._updateChannelGains()
            self._notify(state: self.running ? .running : .idle)
        }
    }

    // MARK: - Anti-Ducking (Bypass call attenuation)

    private static let callBundleIDs: Set<String> = [
        "net.whatsapp.WhatsApp",
        "WhatsApp",
        "com.whatsapp",
        "net.whatsapp.WhatsApp.desktop",
        "com.apple.FaceTime",
        "com.apple.avconferenced",
        "com.apple.telephonyutilities",
        "us.zoom.xos",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.skype.skype",
        "com.discord",
        "com.hammerandchisel.discord",
        "com.tinyspeck.slackmacgap",
        "org.whispersystems.signal-desktop",
        "ru.keepcoder.Telegram",
        "com.telegram.desktop",
        "com.cisco.webexmeetingsapp"
    ]

    private func _isCallChannel(_ ch: EngineChannel) -> Bool {
        if Self.callBundleIDs.contains(ch.identity.bundleID) { return true }
        let lowBid = ch.identity.bundleID.lowercased()
        let lowName = ch.identity.name.lowercased()
        if lowBid.contains("whatsapp") || lowBid.contains("facetime") || lowBid.contains("zoom") ||
           lowBid.contains("teams") || lowBid.contains("discord") || lowBid.contains("skype") ||
           lowBid.contains("slack") || lowBid.contains("call") ||
           lowName.contains("whatsapp") || lowName.contains("facetime") || lowName.contains("zoom") ||
           lowName.contains("teams") || lowName.contains("discord") || lowName.contains("call") {
            return true
        }
        if AudioProcesses.isRunningInput(ch.process.objectID) { return true }
        return false
    }

    func setTestingDucking(_ active: Bool) {
        engineQueue.async { [weak self] in
            guard let self = self else { return }
            self.isTestingDucking = active
            self._updateChannelGains()
            self._notify(state: self.running ? .running : .idle)
        }
    }

    private func _isCallActive() -> Bool {
        if isTestingDucking { return true }
        if HAL.isInputDeviceRunning() { return true }
        return _activeCallAppName() != nil
    }

    private func _activeCallAppName() -> String? {
        if isTestingDucking { return "Simulasi Call" }
        let all = AudioProcesses.all()
        for p in all {
            if let bid = p.bundleID {
                let lowBid = bid.lowercased()
                if Self.callBundleIDs.contains(bid) ||
                    lowBid.contains("whatsapp") ||
                    lowBid.contains("facetime") ||
                    lowBid.contains("zoom") ||
                    lowBid.contains("teams") ||
                    lowBid.contains("skype") ||
                    lowBid.contains("discord") ||
                    lowBid.contains("slack") ||
                    lowBid.contains("avconferenced") {
                    if AudioProcesses.isRunningOutput(p.objectID) || AudioProcesses.isRunningInput(p.objectID) {
                        let id = AppIdentity.resolve(bundleID: p.bundleID, pid: p.pid)
                        return id.name
                    }
                }
            }
            if AudioProcesses.isRunningInput(p.objectID) {
                let id = AppIdentity.resolve(bundleID: p.bundleID, pid: p.pid)
                return id.name
            }
        }
        if HAL.isInputDeviceRunning() {
            return "Microphone / Call"
        }
        return nil
    }

    private func _effectiveGain(for ch: EngineChannel, callActive: Bool) -> Float {
        let userGain = Persistence.gain(for: ch.identity.bundleID)
        if !isAntiDuckingEnabled && callActive && !_isCallChannel(ch) {
            // Standard macOS ducking: reduce background media to 25% (-12 dB)
            return userGain * 0.25
        }
        return userGain
    }

    private func _updateChannelGains() {
        let callActive = _isCallActive()
        let callName = _activeCallAppName()
        var updated: [EngineChannel] = []
        var anyChanged = false

        for ch in channels {
            let isCall = _isCallChannel(ch)
            let isDucked = !isAntiDuckingEnabled && callActive && !isCall
            let eff = _effectiveGain(for: ch, callActive: callActive)
            rt_set_gain(ctx, Int32(ch.slot), eff)

            var newCh = ch
            if newCh.isCallApp != isCall || newCh.isDucked != isDucked {
                newCh.isCallApp = isCall
                newCh.isDucked = isDucked
                anyChanged = true
            }
            updated.append(newCh)
        }
        if anyChanged || callActive != lastCallActive || callName != lastCallAppName {
            lastCallActive = callActive
            lastCallAppName = callName
            channels = updated
            _notify(state: .running)
        }
    }

    private typealias DuckFn = @convention(c)
        (AudioObjectID, Float32, UnsafePointer<AudioTimeStamp>?, Float32) -> OSStatus

    private static let audioDeviceDuck: DuckFn? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let sym = dlsym(handle, "AudioDeviceDuck") else { return nil }
        return unsafeBitCast(sym, to: DuckFn.self)
    }()

    private func _allOutputDeviceIDs() -> [AudioObjectID] {
        var devices = Set<AudioObjectID>()
        if realOutputDevice != 0 { devices.insert(realOutputDevice) }
        if aggregateID != 0 { devices.insert(aggregateID) }
        if let defaultDev = HAL.defaultOutputDevice() { devices.insert(defaultDev) }
        for dev in HAL.outputDevices() {
            devices.insert(dev)
        }
        return Array(devices)
    }

    private func _writeDuckProperty(_ values: [Float32], devices: [AudioObjectID]) {
        let duckSelector = AudioObjectPropertySelector(
            (UInt32(UInt8(ascii: "d")) << 24) |
            (UInt32(UInt8(ascii: "u")) << 16) |
            (UInt32(UInt8(ascii: "c")) << 8)  |
             UInt32(UInt8(ascii: "k"))
        )
        var vals = values
        let size = UInt32(MemoryLayout<Float32>.stride * vals.count)

        for dev in devices {
            for scope in [kAudioDevicePropertyScopeOutput, kAudioObjectPropertyScopeGlobal] {
                var address = AudioObjectPropertyAddress(
                    mSelector: duckSelector,
                    mScope: scope,
                    mElement: kAudioObjectPropertyElementMain
                )
                guard AudioObjectHasProperty(dev, &address) else { continue }
                var settable: DarwinBoolean = false
                guard AudioObjectIsPropertySettable(dev, &address, &settable) == noErr, settable.boolValue else { continue }
                _ = AudioObjectSetPropertyData(dev, &address, 0, nil, size, &vals)
            }
        }
    }

    private func _applyUnduck() {
        guard isAntiDuckingEnabled else { return }
        let devices = _allOutputDeviceIDs()
        _writeDuckProperty([1.0, 0.0, 0.0, 0.0], devices: devices)
    }

    // MARK: - App Scanning & Polling

    private func _refresh() {
        guard running else { return }
        if isAntiDuckingEnabled {
            _applyUnduck()
        }
        _updateChannelGains()
        if !everCreatedTap, let retry = permissionRetryAt, Date() < retry { return }
        let now = Date()
        let excluded = Persistence.excludedBundleIDs
        var desired: [AudioProcess] = []

        let all = AudioProcesses.all()
        let liveIDs = Set(all.map { $0.objectID })

        for p in all {
            let bid = p.bundleID ?? (p.pid > 0 ? "pid.\(p.pid)" : "")
            guard !bid.isEmpty else { continue }
            if excluded.contains(bid) { continue }

            let alreadyTapped = tapsByProcess[p.objectID] != nil
            let active = AudioProcesses.isRunningOutput(p.objectID)

            if active {
                lastActive[p.objectID] = now
                desired.append(p)
            } else if alreadyTapped, let last = lastActive[p.objectID],
                      now.timeIntervalSince(last) < hysteresis {
                desired.append(p)
            }
        }

        lastActive = lastActive.filter { liveIDs.contains($0.key) }

        let desiredIDs = Set(desired.map { $0.objectID })
        let currentIDs = Set(channels.map { $0.process.objectID })
        if desiredIDs != currentIDs {
            _rebuildGraph(desired: desired)
        }
    }

    // MARK: - Graph Build & Teardown

    private func _rebuildGraph(desired: [AudioProcess]) {
        _teardownIO()

        let desiredIDs = Set(desired.map { $0.objectID })
        for (procID, tap) in tapsByProcess where !desiredIDs.contains(procID) {
            AudioHardwareDestroyProcessTap(tap.tapID)
            tapsByProcess.removeValue(forKey: procID)
        }
        for p in desired where tapsByProcess[p.objectID] == nil {
            if let made = _createTap(for: p) {
                tapsByProcess[p.objectID] = made
                everCreatedTap = true
                permissionRetryAt = nil
                log.notice("Tapped process: \(p.bundleID ?? "?", privacy: .public) (PID \(p.pid))")
            } else if !everCreatedTap {
                log.notice("Awaiting audio-capture permission...")
                _notify(state: .permissionNeeded)
                permissionRetryAt = Date().addingTimeInterval(3)
                return
            }
        }

        var newChannels: [EngineChannel] = []
        var slot = 0
        for p in desired {
            guard tapsByProcess[p.objectID] != nil else { continue }
            let identity = AppIdentity.resolve(bundleID: p.bundleID, pid: p.pid)
            rt_reset_slot(ctx, Int32(slot))
            rt_set_gain(ctx, Int32(slot), Persistence.gain(for: identity.bundleID))
            rt_set_mute(ctx, Int32(slot), Persistence.mute(for: identity.bundleID))
            let appOut = Persistence.appOutputUID(for: identity.bundleID)
            newChannels.append(EngineChannel(slot: slot, process: p, identity: identity, outputUID: appOut))
            slot += 1
            if slot >= Int(RT_MAX_SLOTS) { break }
        }
        channels = newChannels
        _updateChannelGains()

        rt_set_master_gain(ctx, Persistence.masterGain)
        rt_set_master_mute(ctx, Persistence.masterMute)

        guard !channels.isEmpty else {
            _notify(state: .running)
            return
        }

        if realOutputUID.isEmpty { _updateRealOutput() }
        guard !realOutputUID.isEmpty else {
            _failSafe("No output device available")
            return
        }

        guard let agg = _createAggregate(outputUID: realOutputUID, channels: channels) else {
            _failSafe("Could not create aggregate audio device")
            return
        }
        aggregateID = agg
        _assignRouting(aggregateID: agg, channels: channels)

        guard _startIO(on: agg) else {
            _failSafe("Could not start audio render")
            return
        }

        log.notice("Mixer running: \(self.channels.count) app(s), output: \(self.realOutputName, privacy: .public)")
        _notify(state: .running)
    }

    private func _createTap(for process: AudioProcess) -> (tapID: AudioObjectID, uid: String)? {
        let desc = CATapDescription(stereoMixdownOfProcesses: [process.objectID])
        desc.name = "WinMix tap \(process.pid)"
        desc.isPrivate = true
        desc.muteBehavior = .mutedWhenTapped
        var tapID = AudioObjectID(0)
        let st = AudioHardwareCreateProcessTap(desc, &tapID)
        guard st == noErr, tapID != 0, let uid = HAL.tapUID(tapID) else {
            if tapID != 0 { AudioHardwareDestroyProcessTap(tapID) }
            return nil
        }
        return (tapID, uid)
    }

    private func _createAggregate(outputUID: String, channels: [EngineChannel]) -> AudioObjectID? {
        let uid = "io.github.winmix.aggregate"
        let tapList: [[String: Any]] = channels.compactMap { ch in
            guard let tap = tapsByProcess[ch.process.objectID] else { return nil }
            return [kAudioSubTapUIDKey as String: tap.uid,
                    kAudioSubTapDriftCompensationKey as String: 1]
        }

        // Include master output device first (Buffer 0)
        var orderedOutputUIDs: [String] = [outputUID]

        // Only add secondary physical output devices if an active channel is explicitly routed to them
        let physicalDevs = HAL.outputDevices()
        let physicalUIDs = Set(physicalDevs.compactMap { HAL.deviceUID($0) })
        for ch in channels {
            if let targetUID = ch.outputUID,
               targetUID != outputUID,
               physicalUIDs.contains(targetUID),
               !orderedOutputUIDs.contains(targetUID) {
                orderedOutputUIDs.append(targetUID)
            }
        }
        activeOutputUIDs = orderedOutputUIDs

        let subDeviceList: [[String: Any]] = orderedOutputUIDs.map { u in
            [kAudioSubDeviceUIDKey as String: u,
             kAudioSubDeviceDriftCompensationKey as String: 1]
        }

        let description: [String: Any] = [
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceNameKey: "WinMix Audio Engine",
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceSubDeviceListKey: subDeviceList,
            kAudioAggregateDeviceTapListKey: tapList
        ]
        var aggID = AudioObjectID(0)
        let st = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggID)
        guard st == noErr, aggID != 0 else {
            return nil
        }
        return aggID
    }

    private func _assignRouting(aggregateID: AudioObjectID, channels: [EngineChannel]) {
        let aggTapList = HAL.aggregateTapUIDs(aggregateID)
        let bufferChannels = HAL.streamChannels(aggregateID, scope: kAudioObjectPropertyScopeInput)

        for ch in channels {
            guard let tap = tapsByProcess[ch.process.objectID] else {
                rt_set_routing(ctx, Int32(ch.slot), -1, 0, 0)
                continue
            }

            // Exactly match the tap UID to its corresponding aggregate input buffer
            let bufIdx: Int
            if let found = aggTapList.firstIndex(of: tap.uid) {
                bufIdx = found
            } else if ch.slot < bufferChannels.count {
                bufIdx = ch.slot
            } else {
                bufIdx = -1
            }

            if bufIdx >= 0 && bufIdx < bufferChannels.count {
                rt_set_routing(ctx, Int32(ch.slot), Int32(bufIdx), 0, 2)
            } else {
                rt_set_routing(ctx, Int32(ch.slot), -1, 0, 0)
            }

            // Route slot to destination output subdevice buffer
            var outBuf = 0
            if let targetUID = ch.outputUID, let idx = activeOutputUIDs.firstIndex(of: targetUID) {
                outBuf = idx
            }
            rt_set_out_buffer(ctx, Int32(ch.slot), Int32(outBuf))
        }
        rt_set_tap_count(ctx, Int32(channels.count))
    }

    func setAppOutput(uid: String?, slot: Int, bundleID: String) {
        engineQueue.async { [weak self] in
            guard let self = self else { return }
            Persistence.setAppOutputUID(uid, for: bundleID)
            if let idx = self.channels.firstIndex(where: { $0.slot == slot }) {
                var ch = self.channels[idx]
                ch.outputUID = uid
                self.channels[idx] = ch
                let desired = self.channels.map { $0.process }
                self._rebuildGraph(desired: desired)
            }
        }
    }

    private func _startIO(on device: AudioObjectID) -> Bool {
        let ctxLocal = ctx
        let block: AudioDeviceIOBlock = { _, inData, _, outData, _ in
            rt_mix_process(ctxLocal, inData, outData)
        }
        var procID: AudioDeviceIOProcID?
        let cst = AudioDeviceCreateIOProcIDWithBlock(&procID, device, ioQueue, block)
        guard cst == noErr, let proc = procID else {
            return false
        }
        ioProcID = proc
        let sst = AudioDeviceStart(device, proc)
        guard sst == noErr else {
            AudioDeviceDestroyIOProcID(device, proc)
            ioProcID = nil
            return false
        }
        return true
    }

    private func _teardownIO() {
        if let proc = ioProcID, aggregateID != 0 {
            AudioDeviceStop(aggregateID, proc)
            AudioDeviceDestroyIOProcID(aggregateID, proc)
        }
        ioProcID = nil
        if aggregateID != 0 {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = 0
        }
        rt_set_tap_count(ctx, 0)
    }

    private func _teardownAll() {
        pollTimer?.cancel(); pollTimer = nil
        if let l = outputListener { HAL.removeListener(l); outputListener = nil }
        _teardownIO()
        for (_, tap) in tapsByProcess { AudioHardwareDestroyProcessTap(tap.tapID) }
        tapsByProcess.removeAll()
        channels.removeAll()
        lastActive.removeAll()
        if let token = activityToken { ProcessInfo.processInfo.endActivity(token); activityToken = nil }
        running = false
    }

    private func _failSafe(_ reason: String) {
        log.error("Fail-safe activated: \(reason, privacy: .public)")
        _teardownIO()
        for (_, tap) in tapsByProcess { AudioHardwareDestroyProcessTap(tap.tapID) }
        tapsByProcess.removeAll()
        channels.removeAll()
        _notify(state: .degraded(reason))
    }

    private func _notify(state: EngineState) {
        let snapshot = EngineSnapshot(
            state: state,
            channels: channels,
            outputDeviceName: realOutputName,
            isCallActive: _isCallActive(),
            activeCallAppName: _activeCallAppName()
        )
        DispatchQueue.main.async { [weak self] in self?.onUpdate?(snapshot) }
    }
}

