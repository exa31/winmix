import CoreAudio
import Foundation
import os

/// One tapped, controllable application audio stream.
struct EngineChannel: Identifiable {
    let slot: Int
    let process: AudioProcess
    let identity: AppIdentity
    var outputUID: String?
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

    private var channels: [EngineChannel] = []
    private var tapsByProcess: [AudioObjectID: (tapID: AudioObjectID, uid: String)] = [:]
    private var lastActive: [AudioObjectID: Date] = [:]

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

    func setGain(_ g: Float, slot: Int)  { rt_set_gain(ctx, Int32(slot), g) }
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

    // MARK: - App Scanning & Polling

    private func _refresh() {
        guard running else { return }
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
        let snapshot = EngineSnapshot(state: state, channels: channels, outputDeviceName: realOutputName)
        DispatchQueue.main.async { [weak self] in self?.onUpdate?(snapshot) }
    }
}

