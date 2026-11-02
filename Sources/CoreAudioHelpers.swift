import CoreAudio
import Foundation
import os

let log = Logger(subsystem: "io.github.winmix", category: "engine")

/// Safe wrappers over the Core Audio HAL property API.
/// Runs on control threads (never in the IOProc callback).
enum HAL {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func has(_ obj: AudioObjectID, _ addr: AudioObjectPropertyAddress) -> Bool {
        var a = addr
        return AudioObjectHasProperty(obj, &a)
    }

    /// Read a fixed-layout scalar cleanly without type-punning warnings.
    static func scalar<T>(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector,
                          scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                          default def: T) -> T? {
        var addr = address(selector, scope: scope)
        var value = def
        var size = UInt32(MemoryLayout<T>.size)
        let st = withUnsafeMutablePointer(to: &value) { ptr in
            AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, ptr)
        }
        return st == noErr ? value : nil
    }

    static func uint32(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector,
                       scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        scalar(obj, selector, scope: scope, default: UInt32(0))
    }

    static func pid(_ obj: AudioObjectID) -> pid_t? {
        scalar(obj, kAudioProcessPropertyPID, default: pid_t(0))
    }

    static func cfString(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> String? {
        var addr = address(selector, scope: scope)
        var unmanaged: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let st = withUnsafeMutablePointer(to: &unmanaged) { ptr in
            AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, ptr)
        }
        guard st == noErr, let u = unmanaged else { return nil }
        return u.takeRetainedValue() as String
    }

    /// Read a variable-length list of values (e.g. process list or device list).
    static func list<T>(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        of: T.Type) -> [T] {
        var addr = address(selector, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(obj, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        let stride = max(1, MemoryLayout<T>.stride)
        let count = Int(size) / stride
        guard count > 0 else { return [] }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: max(1, MemoryLayout<T>.alignment))
        defer { raw.deallocate() }
        let st = AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, raw)
        guard st == noErr else { return [] }
        let bound = raw.bindMemory(to: T.self, capacity: count)
        return Array(UnsafeBufferPointer(start: bound, count: count))
    }

    // MARK: Devices

    static func defaultOutputDevice() -> AudioObjectID? {
        scalar(system, kAudioHardwarePropertyDefaultOutputDevice, default: AudioObjectID(0))
    }

    static func isPhysicalOutput(_ dev: AudioObjectID) -> Bool {
        var transport: UInt32 = 0
        var tSize = UInt32(MemoryLayout<UInt32>.size)
        var tProp = address(kAudioDevicePropertyTransportType)
        if AudioObjectGetPropertyData(dev, &tProp, 0, nil, &tSize, &transport) == noErr {
            let virt: UInt32 = 0x76697274 // 'virt' (virtual loopback devices like MS Teams Audio)
            if transport == virt { return false }
        }
        return true
    }

    static func outputDevices() -> [AudioObjectID] {
        let all = list(system, kAudioHardwarePropertyDevices, of: AudioObjectID.self)
        return all.filter { dev in
            guard isPhysicalOutput(dev) else { return false }
            var addr = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(dev, &addr, 0, nil, &size) == noErr else { return false }
            return size > 0
        }
    }

    static func deviceName(_ obj: AudioObjectID) -> String? {
        cfString(obj, kAudioObjectPropertyName)
    }

    static func deviceUID(_ obj: AudioObjectID) -> String? {
        cfString(obj, kAudioDevicePropertyDeviceUID)
    }

    static func tapUID(_ obj: AudioObjectID) -> String? {
        cfString(obj, kAudioTapPropertyUID)
    }

    static func aggregateTapUIDs(_ obj: AudioObjectID) -> [String] {
        var addr = address(AudioObjectPropertySelector(kAudioAggregateDevicePropertyTapList))
        var unmanaged: Unmanaged<CFPropertyList>?
        var size = UInt32(MemoryLayout<Unmanaged<CFPropertyList>?>.size)
        let st = withUnsafeMutablePointer(to: &unmanaged) { ptr in
            AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, ptr)
        }
        guard st == noErr, let u = unmanaged else { return [] }
        let prop = u.takeRetainedValue()
        if let list = prop as? [String] {
            return list
        }
        return []
    }

    /// Number of channels per buffer in the device's stream.
    static func streamChannels(_ obj: AudioObjectID, scope: AudioObjectPropertyScope) -> [Int] {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(obj, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, raw) == noErr else { return [] }
        let listPtr = raw.assumingMemoryBound(to: AudioBufferList.self)
        let count = Int(listPtr.pointee.mNumberBuffers)
        return withUnsafePointer(to: &listPtr.pointee.mBuffers) { bufPtr in
            (0..<count).map { Int(bufPtr[$0].mNumberChannels) }
        }
    }

    // MARK: Property listeners

    static func addListener(_ obj: AudioObjectID,
                            _ selector: AudioObjectPropertySelector,
                            scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                            queue: DispatchQueue,
                            block: @escaping () -> Void) -> ListenerToken? {
        var addr = address(selector, scope: scope)
        let b: AudioObjectPropertyListenerBlock = { _, _ in block() }
        let st = AudioObjectAddPropertyListenerBlock(obj, &addr, queue, b)
        return st == noErr ? ListenerToken(obj: obj, addr: addr, block: b) : nil
    }

    static func removeListener(_ tok: ListenerToken) {
        var a = tok.addr
        AudioObjectRemovePropertyListenerBlock(tok.obj, &a, nil, tok.block)
    }
}

final class ListenerToken: @unchecked Sendable {
    let obj: AudioObjectID
    let addr: AudioObjectPropertyAddress
    let block: AudioObjectPropertyListenerBlock
    init(obj: AudioObjectID, addr: AudioObjectPropertyAddress, block: @escaping AudioObjectPropertyListenerBlock) {
        self.obj = obj; self.addr = addr; self.block = block
    }
}
