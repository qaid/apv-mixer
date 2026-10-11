import AudioToolbox
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

// MARK: - Output devices (P4)

extension Audio {
    static func outputStreamCount(_ device: AudioObjectID) -> Int {
        var a = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &a, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    /// Devices with output streams whose `flag` property ('dflt' or 'sflt') is 1, by name, ties by UID.
    /// The mixer's own private aggregates are visible to this process, so they are left out by name.
    private static func outputChoices(flag: AudioObjectPropertySelector) -> [OutputChoice] {
        deviceIDs().compactMap { id -> OutputChoice? in
            guard outputStreamCount(id) > 0, value(id, flag, UInt32(0), scope: kAudioObjectPropertyScopeOutput) == 1,
                  let uid = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
            let name = string(id, kAudioObjectPropertyName) ?? uid
            return name.hasPrefix(Engine.namePrefix) ? nil : OutputChoice(uid: uid, name: name)
        }
        .sorted { ($0.name, $0.uid) < ($1.name, $1.uid) }
    }

    /// Devices macOS allows as the default output.
    static func outputDevices() -> [OutputChoice] { outputChoices(flag: kAudioDevicePropertyDeviceCanBeDefaultDevice) }
    /// Devices macOS allows as the sound effects device.
    static func effectsDevices() -> [OutputChoice] { outputChoices(flag: kAudioDevicePropertyDeviceCanBeDefaultSystemDevice) }

    /// Numeric ID for a UID, or nil when no such device is present.
    static func deviceID(uid: String) -> AudioObjectID? {
        deviceIDs().first { string($0, kAudioDevicePropertyDeviceUID) == uid }
    }

    static func defaultSystemOutput() -> AudioObjectID {
        value(system, kAudioHardwarePropertyDefaultSystemOutputDevice, AudioObjectID(0))
    }

    static func setDefaultOutput(_ device: AudioObjectID) {
        var a = address(kAudioHardwarePropertyDefaultOutputDevice)
        var d = device
        AudioObjectSetPropertyData(system, &a, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &d)
    }

    static func setDefaultSystemOutput(_ device: AudioObjectID) {
        var a = address(kAudioHardwarePropertyDefaultSystemOutputDevice)
        var d = device
        AudioObjectSetPropertyData(system, &a, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &d)
    }

    private static func outAddress(_ selector: AudioObjectPropertySelector,
                                   _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeOutput, mElement: element)
    }

    private static func isSettable(_ device: AudioObjectID, _ a: AudioObjectPropertyAddress) -> Bool {
        var a = a
        var ok: DarwinBoolean = false
        return AudioObjectHasProperty(device, &a) && AudioObjectIsPropertySettable(device, &a, &ok) == noErr && ok.boolValue
    }

    private static func getFloat(_ device: AudioObjectID, _ a: AudioObjectPropertyAddress) -> Float? {
        var a = a
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &a, 0, nil, &size, &v) == noErr ? v : nil
    }

    private static func setFloat(_ device: AudioObjectID, _ a: AudioObjectPropertyAddress, _ value: Float) {
        var a = a
        var v = min(max(value, 0), 1)
        AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
    }

    // Output volume: the virtual main volume ('vmvc'), which is what the volume keys change. nil = absent or not settable.
    private static func volumeAddress() -> AudioObjectPropertyAddress { outAddress(kAudioHardwareServiceDeviceProperty_VirtualMainVolume) }

    static func outputVolume(_ device: AudioObjectID) -> Float? {
        isSettable(device, volumeAddress()) ? getFloat(device, volumeAddress()) : nil
    }

    static func setOutputVolume(_ device: AudioObjectID, _ v: Float) { setFloat(device, volumeAddress(), v) }

    // Balance 0...1 (0.5 = centre): StereoPan when the device has it, else the virtual main balance ('vmbc').
    private static func balanceAddress(_ device: AudioObjectID) -> AudioObjectPropertyAddress? {
        for sel in [kAudioDevicePropertyStereoPan, kAudioHardwareServiceDeviceProperty_VirtualMainBalance] {
            let a = outAddress(sel)
            if isSettable(device, a) { return a }
        }
        return nil
    }

    static func outputBalance(_ device: AudioObjectID) -> Float? {
        balanceAddress(device).flatMap { getFloat(device, $0) }
    }

    static func setOutputBalance(_ device: AudioObjectID, _ b: Float) {
        if let a = balanceAddress(device) { setFloat(device, a, b) }
    }

    // Mute on the main element, output scope. nil = absent or not settable.
    private static func muteAddress() -> AudioObjectPropertyAddress { outAddress(kAudioDevicePropertyMute) }

    static func outputMute(_ device: AudioObjectID) -> Bool? {
        let a = muteAddress()
        guard isSettable(device, a) else { return nil }
        var a2 = a
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &a2, 0, nil, &size, &v) == noErr ? v != 0 : nil
    }

    static func setOutputMute(_ device: AudioObjectID, _ muted: Bool) {
        var a = muteAddress()
        var v: UInt32 = muted ? 1 : 0
        AudioObjectSetPropertyData(device, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
    }

    /// Every property the output controls live on: virtual volume and balance, pan, mute (main element) and the scalar volume
    /// on the main, left and right elements, all output scope.
    static func outputControlAddresses() -> [AudioObjectPropertyAddress] {
        [outAddress(kAudioHardwareServiceDeviceProperty_VirtualMainVolume),
         outAddress(kAudioHardwareServiceDeviceProperty_VirtualMainBalance),
         outAddress(kAudioDevicePropertyStereoPan),
         outAddress(kAudioDevicePropertyMute)]
        + [kAudioObjectPropertyElementMain, 1, 2].map { outAddress(kAudioDevicePropertyVolumeScalar, $0) }
    }

    /// Frames of delay for one scope: device latency + safety offset + the first stream's latency.
    static func latencyFrames(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> UInt32 {
        var frames = value(device, kAudioDevicePropertyLatency, UInt32(0), scope: scope)
            + value(device, kAudioDevicePropertySafetyOffset, UInt32(0), scope: scope)
        var a = address(kAudioDevicePropertyStreams, scope)
        var size: UInt32 = 0
        if AudioObjectGetPropertyDataSize(device, &a, 0, nil, &size) == noErr, size >= UInt32(MemoryLayout<AudioStreamID>.size) {
            var streams = [AudioStreamID](repeating: 0, count: Int(size) / MemoryLayout<AudioStreamID>.size)
            if AudioObjectGetPropertyData(device, &a, 0, nil, &size, &streams) == noErr, let first = streams.first {
                frames += value(first, kAudioStreamPropertyLatency, UInt32(0))
            }
        }
        return frames
    }
}
