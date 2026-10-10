import CoreAudio
import Foundation

struct InputDevice {
    let id: AudioObjectID   // numeric ID: valid only for this plug-in, never stored (spec 7.10)
    let uid: String
    let name: String
}

/// Thin Core Audio property helpers. All run on the main thread.
enum Audio {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func value<T: BitwiseCopyable>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ initial: T,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> T {
        var a = address(selector, scope)
        var v = initial
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &a, 0, nil, &size, &v) == noErr ? v : initial
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var a = address(selector)
        var s: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(object, &a, 0, nil, &size, &s) == noErr, let s else { return nil }
        return s.takeRetainedValue() as String
    }

    static func deviceIDs() -> [AudioObjectID] {
        var a = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    static func inputStreamCount(_ device: AudioObjectID) -> Int {
        var a = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &a, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    /// Channels per input buffer (one entry per input stream), in buffer order.
    static func inputBufferChannels(_ device: AudioObjectID) -> [Int] {
        var a = address(kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &a, 0, nil, &size, raw) == noErr else { return [] }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.map { Int($0.mNumberChannels) }
    }

    /// Every hardware device that has input streams, sorted by device name, ties by UID (a rename never moves a strip).
    /// Software devices (virtual, aggregate, unknown transport) are left out (spec 3.1).
    static func inputDevices() -> [InputDevice] {
        let software: Set<UInt32> = [kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate,
                                     kAudioDeviceTransportTypeAutoAggregate, kAudioDeviceTransportTypeUnknown]
        return deviceIDs().compactMap { id -> InputDevice? in
            guard inputStreamCount(id) > 0, let uid = string(id, kAudioDevicePropertyDeviceUID),
                  !software.contains(value(id, kAudioDevicePropertyTransportType, UInt32(0))) else { return nil }
            return InputDevice(id: id, uid: uid, name: string(id, kAudioObjectPropertyName) ?? uid)
        }
        .sorted { ($0.name, $0.uid) < ($1.name, $1.uid) }
    }

    static func defaultOutput() -> AudioObjectID {
        value(system, kAudioHardwarePropertyDefaultOutputDevice, AudioObjectID(0))
    }
}

extension Audio {
    static func defaultInput() -> AudioObjectID {
        value(system, kAudioHardwarePropertyDefaultInputDevice, AudioObjectID(0))
    }

    static func setDefaultInput(_ device: AudioObjectID) {
        var a = address(kAudioHardwarePropertyDefaultInputDevice)
        var d = device
        AudioObjectSetPropertyData(system, &a, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &d)
    }

    /// Elements that carry the input volume: the main element, else left and right. Empty = no settable volume.
    private static func volumeElements(_ device: AudioObjectID) -> [AudioObjectPropertyElement] {
        func settable(_ e: AudioObjectPropertyElement) -> Bool {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                               mScope: kAudioObjectPropertyScopeInput, mElement: e)
            var ok: DarwinBoolean = false
            return AudioObjectHasProperty(device, &a) && AudioObjectIsPropertySettable(device, &a, &ok) == noErr && ok.boolValue
        }
        if settable(kAudioObjectPropertyElementMain) { return [kAudioObjectPropertyElementMain] }
        return [1, 2].filter(settable)
    }

    /// Input volume 0...1 (average over the elements), or nil when the device has no settable volume.
    static func inputVolume(_ device: AudioObjectID) -> Float? {
        let elements = volumeElements(device)
        guard !elements.isEmpty else { return nil }
        var sum: Float = 0
        for e in elements {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                               mScope: kAudioObjectPropertyScopeInput, mElement: e)
            var v: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &a, 0, nil, &size, &v) == noErr else { return nil }
            sum += v
        }
        return sum / Float(elements.count)
    }

    static func setInputVolume(_ device: AudioObjectID, _ volume: Float) {
        var v = min(max(volume, 0), 1)
        for e in volumeElements(device) {
            var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                               mScope: kAudioObjectPropertyScopeInput, mElement: e)
            AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        }
    }

    /// Elements to listen on for volume changes (main, left, right).
    static func volumeAddresses() -> [AudioObjectPropertyAddress] {
        [kAudioObjectPropertyElementMain, 1, 2].map {
            AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                       mScope: kAudioObjectPropertyScopeInput, mElement: $0)
        }
    }
}
