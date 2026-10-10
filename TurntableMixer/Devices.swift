import CoreAudio
import Foundation

struct InputDevice {
    let id: AudioObjectID   // numeric ID: valid only for this plug-in, never stored (spec 7.10)
    let uid: String
    let name: String
    let transport: UInt32
}

/// One process object from Core Audio's process list.
struct AudioProcess {
    let object: AudioObjectID
    let pid: Int32
    let bundleID: String?
    let runningOutput: Bool     // IsRunningOutput: the process has an output stream running
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
            return InputDevice(id: id, uid: uid, name: string(id, kAudioObjectPropertyName) ?? uid,
                               transport: value(id, kAudioDevicePropertyTransportType, UInt32(0)))
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

// MARK: - Icons, processes, taps

extension Audio {
    /// SF Symbol for an input strip, by transport type.
    static func symbol(transport: UInt32) -> String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: "mic"
        case kAudioDeviceTransportTypeUSB: "cable.connector"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: "headphones"
        case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless: "iphone"
        default: "waveform"
        }
    }

    static func isBluetooth(_ device: AudioObjectID) -> Bool {
        let t = value(device, kAudioDevicePropertyTransportType, UInt32(0))
        return t == kAudioDeviceTransportTypeBluetooth || t == kAudioDeviceTransportTypeBluetoothLE
    }

    private static func objectList(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var a = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    /// Every process object Core Audio knows about.
    static func processes() -> [AudioProcess] {
        objectList(system, kAudioHardwarePropertyProcessObjectList).map {
            AudioProcess(object: $0, pid: value($0, kAudioProcessPropertyPID, Int32(0)),
                         bundleID: string($0, kAudioProcessPropertyBundleID),
                         runningOutput: value($0, kAudioProcessPropertyIsRunningOutput, UInt32(0)) != 0)
        }
    }

    /// Creates a private tap that mutes the processes' normal output while tapped (spec D3).
    /// Returns the tap's ID, or nil on failure (for example when System Audio Recording is refused).
    static func makeTap(processes: [AudioObjectID], name: String) -> (id: AudioObjectID, description: CATapDescription)? {
        let desc = CATapDescription(stereoMixdownOfProcesses: processes)
        desc.uuid = UUID()
        desc.isPrivate = true
        desc.muteBehavior = .mutedWhenTapped
        desc.name = name
        var id = AudioObjectID(0)
        guard AudioHardwareCreateProcessTap(desc, &id) == noErr, id != 0 else { return nil }
        return (id, desc)
    }

    /// Replaces the processes of a live tap. False when Core Audio refuses.
    static func setTapProcesses(_ tap: AudioObjectID, _ description: CATapDescription, _ processes: [AudioObjectID]) -> Bool {
        description.processes = processes
        var ref = Unmanaged.passUnretained(description)
        var a = address(kAudioTapPropertyDescription)
        return AudioObjectSetPropertyData(tap, &a, 0, nil, UInt32(MemoryLayout<Unmanaged<CATapDescription>>.size), &ref) == noErr
    }

    /// Launch cleanup (spec 7.13): destroys aggregates and taps this app left behind, found by name prefix.
    /// ponytail: a probe shows private objects vanish with their process, so this is a safety net only.
    static func destroyLeftovers() {
        for id in deviceIDs() where (string(id, kAudioObjectPropertyName) ?? "").hasPrefix(Engine.namePrefix) {
            AudioHardwareDestroyAggregateDevice(id)
        }
        for tap in objectList(system, kAudioHardwarePropertyTapList) {
            var a = address(kAudioTapPropertyDescription)
            var ref: Unmanaged<CATapDescription>?
            var size = UInt32(MemoryLayout<Unmanaged<CATapDescription>>.size)
            // Unretained: at worst this leaks one small object, never over-releases.
            guard AudioObjectGetPropertyData(tap, &a, 0, nil, &size, &ref) == noErr,
                  let name = ref?.takeUnretainedValue().name, name.hasPrefix(Engine.tapNamePrefix) else { continue }
            AudioHardwareDestroyProcessTap(tap)
        }
    }
}
