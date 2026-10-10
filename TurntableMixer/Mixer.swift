import AppKit
import AVFoundation
import CoreAudio
import Observation

/// One input strip. The model owns every write; the UI reads. Main thread only.
@Observable final class Strip: Identifiable {
    let uid: String                                   // device UID (spec 7.10)
    var id: String { uid }
    fileprivate(set) var deviceName: String
    fileprivate(set) var savedName: String?
    fileprivate(set) var connected = true             // false: the device went away this session
    fileprivate(set) var position: Float = 0          // level knob 0...1 in Gain's position scale; 0 = silent (D4)
    fileprivate(set) var trimDB: Float = 0            // -24...+24
    fileprivate(set) var muted = false
    fileprivate(set) var needleDB: Float = Mixer.needleFloorDB   // post-gain level, VU ballistics applied
    fileprivate(set) var clipLit = false              // latched until clearClip
    fileprivate(set) var noSignal = false
    fileprivate(set) var isDefaultInput = false
    fileprivate(set) var deviceGain: Float?           // macOS input volume 0...1; nil = the device has none

    var displayName: String { savedName ?? deviceName }
    var db: Float { Gain.db(at: position) }

    @ObservationIgnored fileprivate var deviceID = AudioObjectID(0)   // numeric ID, valid this session only
    @ObservationIgnored fileprivate var wanted = false                // should be an engine member (position above 0, or waiting out the 1 s hold)
    @ObservationIgnored fileprivate var slot: Int?                    // engine slot while a member
    @ObservationIgnored fileprivate var removal: Task<Void, Never>?   // pending leave after 1 s at 0
    @ObservationIgnored fileprivate var lastLoud = Date()
    @ObservationIgnored fileprivate var volumeID = AudioObjectID(0)   // device the volume listener sits on
    @ObservationIgnored fileprivate var volumeBlock: AudioObjectPropertyListenerBlock?

    fileprivate init(uid: String, deviceName: String, saved: [String: Any]?) {
        self.uid = uid
        self.deviceName = deviceName
        savedName = saved?["name"] as? String
        trimDB = Float(min(max(saved?["trim"] as? Double ?? 0, -24), 24))
        position = Float(min(max(saved?["fader"] as? Double ?? 0, 0), 1))   // D4: new devices start silent
        muted = saved?["mute"] as? Bool ?? false
    }
}

/// Mixer state: one strip per hardware input device. Main thread only.
@Observable final class Mixer {
    static let shared = Mixer()

    private(set) var strips: [Strip] = []     // by device name, ties by UID: renaming never moves a strip
    private(set) var micDenied = false
    private(set) var engineError: String?

    @ObservationIgnored private let engine = Engine()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var runningKey: EngineKey?
    @ObservationIgnored private var lastTick = Date()
    @ObservationIgnored private var lastMicStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @ObservationIgnored private var listeners: [AudioObjectPropertyListenerBlock] = []
    // Loaded once, written through on every change (spec 3.7). By UID: name, trim (dB), fader (position), mute.
    @ObservationIgnored private var saved = UserDefaults.standard.dictionary(forKey: Mixer.inputDevicesKey) as? [String: [String: Any]] ?? [:]

    private static let inputDevicesKey = "inputDevices"
    static let needleFloorDB: Float = -60
    private static let needleSeconds: Float = 0.3     // VU ballistics time constant
    private static let leaveDelay = 1.0               // seconds at 0 before a strip leaves the engine
    // Raw input below this for `noSignalSeconds` means the source is off (measured: off peaks about -78 dBFS, on with needle up peaks above -72 dBFS). Calibration knob.
    static let noSignalDB: Float = -75
    static let noSignalSeconds = 3.0

    func start() {
        guard !started else { return }
        started = true

        updateMicStatus()
        if lastMicStatus == .notDetermined {
            Task { _ = await AVCaptureDevice.requestAccess(for: .audio); self.updateMicStatus() }
        }

        listen(kAudioHardwarePropertyDevices) { $0.refresh() }
        listen(kAudioHardwarePropertyDefaultOutputDevice) { $0.reconcile() }   // plugging in headphones moves playback (AC11)
        listen(kAudioHardwarePropertyDefaultInputDevice) { $0.updateDefaultInput() }

        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMicStatus() }
        }
        nc.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.engine.stop() }   // destroys the aggregate
        }
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        refresh()
    }

    private func listen(_ selector: AudioObjectPropertySelector, _ action: @escaping (Mixer) -> Void) {
        var address = Audio.address(selector)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }
        listeners.append(block)
        AudioObjectAddPropertyListenerBlock(Audio.system, &address, DispatchQueue.main, block)
    }

    // MARK: Strips and engine

    /// Called on every device list change.
    func refresh() {
        let devices = Audio.inputDevices()
        var list = strips
        for d in devices {
            let strip: Strip
            if let existing = list.first(where: { $0.uid == d.uid }) {
                strip = existing
                if !strip.connected { strip.connected = true; strip.wanted = strip.position > 0 }
            } else {
                strip = Strip(uid: d.uid, deviceName: d.name, saved: saved[d.uid])
                strip.wanted = strip.position > 0
                list.append(strip)
            }
            if strip.deviceName != d.name { strip.deviceName = d.name }
            strip.deviceID = d.id
        }
        // A device that went away keeps its strip, greyed, with its settings.
        for strip in list where strip.connected && !devices.contains(where: { $0.uid == strip.uid }) {
            strip.connected = false
            strip.wanted = false
            strip.removal?.cancel(); strip.removal = nil
            strip.isDefaultInput = false
            strip.deviceGain = nil
            strip.needleDB = Self.needleFloorDB
            strip.noSignal = false
        }
        list.sort { ($0.deviceName, $0.uid) < ($1.deviceName, $1.uid) }
        if list.map(\.uid) != strips.map(\.uid) { strips = list }

        for strip in list { watchVolume(strip) }
        updateDefaultInput()
        reconcile()
    }

    /// Rebuilds the aggregate when its key changed (or when forced). Members: connected strips that want in.
    private func reconcile(force: Bool = false) {
        // ponytail: members beyond the engine's slot capacity are left out.
        let members = Array(strips.filter { $0.connected && $0.wanted }.prefix(Engine.maxStrips))
        var key: EngineKey?
        let out = Audio.defaultOutput()
        if !members.isEmpty, out != 0, let outUID = Audio.string(out, kAudioDevicePropertyDeviceUID) {
            key = EngineKey(output: EngineDevice(uid: outUID, id: out),
                            members: members.map { EngineDevice(uid: $0.uid, id: $0.deviceID) })
        }
        guard force || key != runningKey else { return }
        // Set before starting: creating our own aggregate fires a device list change, which comes back here.
        runningKey = key

        let now = Date()
        for strip in strips { strip.lastLoud = now; strip.slot = nil }
        guard let key else {
            engine.stop()
            engineError = members.isEmpty ? nil : "No output device."
            return
        }
        engineError = engine.start(key: key, targets: members.map(target))
        if engineError == nil {
            for (i, strip) in members.enumerated() { strip.slot = i }
        }
    }

    private func target(_ s: Strip) -> Float {
        s.muted ? 0 : Gain.linear(db: s.trimDB) * Gain.linear(at: s.position)
    }

    private func pushGain(_ s: Strip) {
        if let slot = s.slot { engine.setTarget(slot: slot, target(s)) }
    }

    private func persist(_ s: Strip) {
        var entry = saved[s.uid] ?? [:]
        if let name = s.savedName { entry["name"] = name } else { entry["name"] = nil }
        entry["trim"] = Double(s.trimDB)
        entry["fader"] = Double(s.position)
        entry["mute"] = s.muted
        saved[s.uid] = entry
        UserDefaults.standard.set(saved, forKey: Self.inputDevicesKey)
    }

    // MARK: Controls

    func setPosition(_ s: Strip, _ p: Float) {
        let p = min(max(p, 0), 1)
        guard p != s.position else { return }
        s.position = p
        persist(s)
        if p > 0 {
            s.removal?.cancel(); s.removal = nil
            if s.connected, !s.wanted { s.wanted = true; reconcile() }   // raised from 0: rebuild at once
        } else if s.wanted, s.removal == nil {
            // Fell to 0: leave the engine only after 1 s at 0 (a rise cancels this).
            s.removal = Task { [weak self, weak s] in
                try? await Task.sleep(for: .seconds(Self.leaveDelay))
                guard !Task.isCancelled, let self, let s, s.position == 0 else { return }
                s.removal = nil
                s.wanted = false
                self.reconcile()
            }
        }
        pushGain(s)
    }

    func setTrim(_ s: Strip, _ db: Float) {
        let v = min(max(db, -24), 24)
        guard v != s.trimDB else { return }
        s.trimDB = v
        persist(s)
        pushGain(s)
    }

    func toggleMute(_ s: Strip) {
        s.muted.toggle()   // mute is a gain of 0; membership does not change
        persist(s)
        pushGain(s)
    }

    func rename(_ s: Strip, _ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        s.savedName = trimmed.isEmpty ? nil : trimmed
        persist(s)
    }

    func clearClip(_ s: Strip) { s.clipLit = false }

    func makeDefaultInput(_ s: Strip) {
        guard s.connected else { return }
        Audio.setDefaultInput(s.deviceID)
    }

    func setDeviceGain(_ s: Strip, _ v: Float) {
        guard s.connected, s.deviceGain != nil else { return }
        let v = min(max(v, 0), 1)
        Audio.setInputVolume(s.deviceID, v)
        s.deviceGain = v
    }

    // MARK: Device state

    private func updateDefaultInput() {
        let d = Audio.defaultInput()
        for s in strips {
            let isDefault = s.connected && s.deviceID == d
            if s.isDefaultInput != isDefault { s.isDefaultInput = isDefault }
        }
    }

    /// Reads the device gain and keeps one listener per device. Never writes the value back (spec 7.9).
    private func watchVolume(_ s: Strip) {
        guard s.connected else { removeVolumeListener(s); return }
        if s.volumeID != s.deviceID {
            removeVolumeListener(s)
            let block: AudioObjectPropertyListenerBlock = { [weak self, weak s] _, _ in
                MainActor.assumeIsolated { if let self, let s { self.volumeChanged(s) } }
            }
            for var a in Audio.volumeAddresses() {
                AudioObjectAddPropertyListenerBlock(s.deviceID, &a, DispatchQueue.main, block)
            }
            s.volumeID = s.deviceID
            s.volumeBlock = block
        }
        volumeChanged(s)
    }

    private func removeVolumeListener(_ s: Strip) {
        if let block = s.volumeBlock {
            for var a in Audio.volumeAddresses() {
                AudioObjectRemovePropertyListenerBlock(s.volumeID, &a, DispatchQueue.main, block)
            }
        }
        s.volumeID = 0
        s.volumeBlock = nil
    }

    private func volumeChanged(_ s: Strip) {
        let g = Audio.inputVolume(s.deviceID)
        if g != s.deviceGain { s.deviceGain = g }   // an equal value is ignored
    }

    // MARK: Meters

    private func tick() {
        let now = Date()
        let dt = Float(min(max(now.timeIntervalSince(lastTick), 0.001), 0.2))
        lastTick = now
        let alpha = 1 - exp(-dt / Self.needleSeconds)
        let peaks = engine.takePeaks()
        for s in strips {
            guard let i = s.slot, i < peaks.count else {
                // Not in the engine: rest at the floor, no "No signal".
                if s.needleDB != Self.needleFloorDB { s.needleDB = Self.needleFloorDB }
                if s.noSignal { s.noSignal = false }
                continue
            }
            let p = peaks[i]
            let level = p.peak > 0 ? max(20 * log10(p.peak), Self.needleFloorDB) : Self.needleFloorDB
            var needle = s.needleDB + alpha * (level - s.needleDB)
            if needle < Self.needleFloorDB + 0.1 { needle = Self.needleFloorDB }
            if abs(needle - s.needleDB) > 0.01 || needle == Self.needleFloorDB && s.needleDB != needle { s.needleDB = needle }

            if p.input > 0, 20 * log10(p.input) >= Self.noSignalDB { s.lastLoud = now }
            let quiet = now.timeIntervalSince(s.lastLoud) > Self.noSignalSeconds
            if s.noSignal != quiet { s.noSignal = quiet }
            if p.clipped, !s.clipLit { s.clipLit = true }
        }
    }

    // MARK: Microphone permission

    func updateMicStatus() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        micDenied = status == .denied || status == .restricted
        if status == .authorized, lastMicStatus != .authorized {
            reconcile(force: true)   // rebuild so the inputs start delivering audio
        }
        lastMicStatus = status
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
