import AppKit
import AVFoundation
import CoreAudio
import Observation
import os

/// One strip: an input device or an app. The model owns every write; the UI reads. Main thread only.
@Observable final class Strip: Identifiable {
    let uid: String                                   // device UID (spec 7.10), or the app's bundle ID
    let isApp: Bool
    var id: String { uid }
    fileprivate(set) var deviceName: String
    fileprivate(set) var savedName: String?
    fileprivate(set) var connected = true             // false: the device went away this session
    fileprivate(set) var position: Float = 0          // level knob 0...1 in Gain's position scale; 0 = silent (D4)
    fileprivate(set) var trimDB: Float = 0            // -24...+24
    fileprivate(set) var muted = false
    fileprivate(set) var needleDB: Float = Mixer.needleFloorDB   // post-gain level, VU ballistics applied
    fileprivate(set) var clip: Float = 0              // clip light 0...1: full while clipping, fades out over ClipFade.seconds
    fileprivate(set) var noSignal = false
    fileprivate(set) var isDefaultInput = false
    fileprivate(set) var deviceGain: Float?           // macOS input volume 0...1; nil = the device has none
    fileprivate(set) var icon: NSImage?               // app strips: the app's icon
    fileprivate(set) var symbol = "waveform"          // input strips: SF Symbol by transport type
    fileprivate(set) var error: String?               // app strips: why the app's engine is down

    var displayName: String { savedName ?? deviceName }
    var db: Float { Gain.db(at: position) }

    @ObservationIgnored fileprivate var deviceID = AudioObjectID(0)   // numeric ID, valid this session only
    @ObservationIgnored fileprivate var wanted = false                // should be an engine member (position above 0, or waiting out the 1 s hold)
    @ObservationIgnored fileprivate var slot: Int?                    // engine slot while a member
    @ObservationIgnored fileprivate var removal: Task<Void, Never>?   // pending leave after 1 s at 0
    @ObservationIgnored fileprivate var lastLoud = Date()
    @ObservationIgnored fileprivate var volumeID = AudioObjectID(0)   // device the volume listener sits on
    @ObservationIgnored fileprivate var volumeBlock: AudioObjectPropertyListenerBlock?
    // App strips only. Each app has its own engine, so one app starting a sound never interrupts the others.
    @ObservationIgnored fileprivate var engine: Engine?
    @ObservationIgnored fileprivate var engineKey: EngineKey?
    @ObservationIgnored fileprivate var processes: [AudioObjectID] = []   // the app's process objects
    @ObservationIgnored fileprivate var running = false                   // any process has IsRunningOutput
    @ObservationIgnored fileprivate var tapID = AudioObjectID(0)
    @ObservationIgnored fileprivate var tapDescription: CATapDescription?
    @ObservationIgnored fileprivate var lastTapAudio = Date()             // last time the tap gave non-zero audio (or nothing was expected)

    fileprivate init(uid: String, deviceName: String, saved: [String: Any]?, isApp: Bool = false) {
        self.uid = uid
        self.isApp = isApp
        self.deviceName = deviceName
        savedName = saved?["name"] as? String
        trimDB = Float(min(max(saved?["trim"] as? Double ?? 0, -24), 24))
        // D4: new devices start silent, new apps at 0 dB.
        position = Float(min(max(saved?["fader"] as? Double ?? Double(isApp ? Gain.detent : 0), 0), 1))
        muted = saved?["mute"] as? Bool ?? false
    }
}

/// Mixer state: one strip per hardware input device and one per app that plays audio. Main thread only.
@Observable final class Mixer {
    static let shared = Mixer()

    private(set) var strips: [Strip] = []     // by device name, ties by UID: renaming never moves a strip
    private(set) var apps: [Strip] = []      // by name, ties by bundle ID
    private(set) var micDenied = false
    private(set) var captureMaybeOff = false  // tapped apps report output but the taps are silent (spec 5)
    /// The input engine's problem; each app strip carries its own `error`.
    private(set) var inputError: String?

    @ObservationIgnored private let engine = Engine()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var runningKey: EngineKey?
    @ObservationIgnored private var lastTick = Date()
    @ObservationIgnored private var lastMicStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @ObservationIgnored private var listeners: [AudioObjectPropertyListenerBlock] = []
    @ObservationIgnored private var processBlock: AudioObjectPropertyListenerBlock?
    @ObservationIgnored private var watchedProcesses: Set<AudioObjectID> = []   // process objects with IsRunning and IsRunningOutput listeners
    @ObservationIgnored private var captureConfirmed = false                    // a tap has delivered audio this session
    @ObservationIgnored private var savedApps = UserDefaults.standard.dictionary(forKey: Mixer.appsKey) as? [String: [String: Any]] ?? [:]
    // Loaded once, written through on every change (spec 3.7). By UID: name, trim (dB), fader (position), mute.
    @ObservationIgnored private var saved = UserDefaults.standard.dictionary(forKey: Mixer.inputDevicesKey) as? [String: [String: Any]] ?? [:]

    private static let inputDevicesKey = "inputDevices"
    private static let appsKey = "apps"
    private static let silentTapSeconds = 2.0         // IsRunningOutput but only zeros for this long: capture may be off
    static let needleFloorDB: Float = -60
    private static let needleSeconds: Float = 0.3     // VU ballistics time constant
    private static let leaveDelay = 1.0               // seconds at 0 before a strip leaves the engine
    // Raw input below this for `noSignalSeconds` means the source is off (measured: off peaks about -78 dBFS, on with needle up peaks above -72 dBFS). Calibration knob.
    static let noSignalDB: Float = -75
    static let noSignalSeconds = 3.0

    func start() {
        guard !started else { return }
        started = true

        Audio.destroyLeftovers()   // before any engine exists (spec 7.13)
        updateMicStatus()
        if lastMicStatus == .notDetermined {
            Task { _ = await AVCaptureDevice.requestAccess(for: .audio); self.updateMicStatus() }
        }

        listen(kAudioHardwarePropertyDevices) { $0.refresh() }
        listen(kAudioHardwarePropertyDefaultOutputDevice) { $0.reconcile(); $0.reconcileApps() }   // plugging in headphones moves playback (AC11)
        listen(kAudioHardwarePropertyProcessObjectList) { $0.refreshApps() }
        listen(kAudioHardwarePropertyDefaultInputDevice) { $0.updateDefaultInput() }

        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMicStatus() }
        }
        nc.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {   // destroys the aggregates and the taps: apps play normally again
                self?.engine.stop()
                for s in self?.apps ?? [] { self?.stopApp(s) }
            }
        }
        Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        refresh()
        refreshApps()
        if UserDefaults.standard.bool(forKey: "selfCheckLog") {   // opt-in: scripts/self-check.sh
            let log = Logger(subsystem: "io.github.qaid.turntablemixer", category: "selfcheck")
            Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    for (kind, list) in [("input", self.strips), ("app", self.apps)] {
                        for s in list {
                            log.notice("\(kind, privacy: .public) name=\(s.displayName, privacy: .public) needleDB=\(s.needleDB, format: .fixed(precision: 1), privacy: .public) muted=\(s.muted, privacy: .public) noSignal=\(s.noSignal, privacy: .public) error=\(s.error ?? "none", privacy: .public)")
                        }
                    }
                    log.notice("captureMaybeOff=\(self.captureMaybeOff, privacy: .public)")
                }
            }
        }
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
                strip.symbol = Audio.symbol(transport: d.transport)
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
        reconcileApps()   // a USB hub reset can change the output's numeric ID
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
            inputError = members.isEmpty ? nil : "No output device."
            return
        }
        inputError = engine.start(key: key, targets: members.map(target))
        if inputError == nil {
            for (i, strip) in members.enumerated() { strip.slot = i }
        }
    }

    private func target(_ s: Strip) -> Float {
        s.muted ? 0 : Gain.linear(db: s.trimDB) * Gain.linear(at: s.position)
    }

    private func pushGain(_ s: Strip) {
        if let slot = s.slot { (s.engine ?? engine).setTarget(slot: slot, target(s)) }
    }

    private func persist(_ s: Strip) {
        var entry = (s.isApp ? savedApps[s.uid] : saved[s.uid]) ?? [:]
        if let name = s.savedName { entry["name"] = name } else { entry["name"] = nil }
        entry["trim"] = Double(s.trimDB)
        entry["fader"] = Double(s.position)
        entry["mute"] = s.muted
        if s.isApp {
            savedApps[s.uid] = entry
            UserDefaults.standard.set(savedApps, forKey: Self.appsKey)
        } else {
            saved[s.uid] = entry
            UserDefaults.standard.set(saved, forKey: Self.inputDevicesKey)
        }
    }

    // MARK: Controls

    func setPosition(_ s: Strip, _ p: Float) {
        let p = min(max(p, 0), 1)
        guard p != s.position else { return }
        s.position = p
        persist(s)
        if s.isApp {
            // The tap stays while the strip exists: removing it would un-mute the app (spec D3). Bottom = gain 0.
        } else if p > 0 {
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
            meter(s, s.slot.flatMap { $0 < peaks.count ? peaks[$0] : nil }, alpha, dt, now)
        }

        // App strips: the same meters, never "No signal". Also watch for taps that stay silent (spec 5).
        var live = false, silent = false
        for s in apps {
            let p = s.slot == nil ? nil : s.engine?.takePeaks().first
            meter(s, p, alpha, dt, now)
            if let p, p.input > 0 { live = true; s.lastTapAudio = now }
            else if !s.running || p == nil { s.lastTapAudio = now }
            if now.timeIntervalSince(s.lastTapAudio) > Self.silentTapSeconds { silent = true }
        }
        // ponytail: one app tapped successfully proves the permission, so a paused app's zeros no longer raise the banner.
        if live { captureConfirmed = true }
        let off = silent && !live && !captureConfirmed
        if captureMaybeOff != off { captureMaybeOff = off }
    }

    /// Moves one strip's needle, "No signal" (input strips) and clip light from the latest peaks. nil = not in an engine.
    private func meter(_ s: Strip, _ p: (peak: Float, input: Float, clipped: Bool)?, _ alpha: Float, _ dt: Float, _ now: Date) {
        guard let p else {
            // Not in the engine: rest at the floor, no "No signal".
            if s.needleDB != Self.needleFloorDB { s.needleDB = Self.needleFloorDB }
            if s.noSignal { s.noSignal = false }
            if s.clip != 0 { s.clip = 0 }
            return
        }
        let level = p.peak > 0 ? max(20 * log10(p.peak), Self.needleFloorDB) : Self.needleFloorDB
        var needle = s.needleDB + alpha * (level - s.needleDB)
        if needle < Self.needleFloorDB + 0.1 { needle = Self.needleFloorDB }
        if abs(needle - s.needleDB) > 0.01 || needle == Self.needleFloorDB && s.needleDB != needle { s.needleDB = needle }

        if !s.isApp {
            if p.input > 0, 20 * log10(p.input) >= Self.noSignalDB { s.lastLoud = now }
            let quiet = now.timeIntervalSince(s.lastLoud) > Self.noSignalSeconds
            if s.noSignal != quiet { s.noSignal = quiet }
        }
        let clip = ClipFade.next(current: s.clip, clipped: p.clipped, dt: dt)
        if clip != s.clip, clip == 0 || clip == 1 || abs(clip - s.clip) > 0.01 { s.clip = clip }
    }

    // MARK: App strips

    /// Called when the process list or a process's output state changes. Idempotent.
    /// A strip appears when any process of the app has `IsRunningOutput` (not `IsRunning`, which is also true for a process that
    /// only holds an input stream open), stays while any of its process objects exists, and goes when none remain.
    /// ponytail: when the strip appears relative to the first sound is unverified on hardware.
    func refreshApps() {
        let all = Audio.processes()
        watchProcesses(all.map(\.object))

        struct Group { var processes: [AudioObjectID] = []; var running = false; var pid: Int32; var appPID: Int32? }
        var groups: [String: Group] = [:]
        for p in all where p.pid > 0 && p.pid != getpid() {   // never tap the mixer itself (spec 7.12)
            let appPID = Grouping.parentApp(of: p.pid, ppid: Grouping.parentPID, isApp: Grouping.isApp)
            // A helper with no parent app gets its own strip, keyed by its own bundle ID.
            guard let key = appPID.flatMap({ NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }) ?? p.bundleID,
                  !key.isEmpty else { continue }
            var g = groups[key] ?? Group(pid: p.pid, appPID: appPID)
            g.processes.append(p.object)
            g.running = g.running || p.runningOutput
            groups[key] = g
        }

        var list = apps
        for (key, g) in groups {
            if let s = list.first(where: { $0.uid == key }) {
                s.running = g.running
                if s.processes != g.processes { updateTap(s, g.processes) }
            } else if g.running {
                let (name, icon) = describe(bundleID: key, pid: g.appPID ?? g.pid)
                let s = Strip(uid: key, deviceName: name, saved: savedApps[key], isApp: true)
                s.icon = icon
                s.processes = g.processes
                s.running = true
                s.engine = Engine()
                list.append(s)
                rebuildTap(s)
            }
        }
        for s in list where groups[s.uid] == nil { stopApp(s) }
        list.removeAll { groups[$0.uid] == nil }
        list.sort { ($0.deviceName, $0.uid) < ($1.deviceName, $1.uid) }
        if list.map(\.uid) != apps.map(\.uid) { apps = list }
    }

    /// A readable name and the icon: the running app's own, else the last bundle-ID component.
    private func describe(bundleID: String, pid: Int32) -> (String, NSImage?) {
        let app = NSRunningApplication(processIdentifier: pid)
        let fallback = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        return (app?.localizedName ?? fallback, app?.icon ?? app?.bundleURL.map { NSWorkspace.shared.icon(forFile: $0.path) })
    }

    /// IsRunning and IsRunningOutput listeners on each process object.
    private func watchProcesses(_ objects: [AudioObjectID]) {
        let block = processBlock ?? { [weak self] _, _ in MainActor.assumeIsolated { self?.refreshApps() } }
        processBlock = block
        let now = Set(objects)
        // A probe on macOS 27 saw only IsRunning notices when playback started, never IsRunningOutput ones.
        // refreshApps reads IsRunningOutput itself, so either notice is enough.
        let selectors = [kAudioProcessPropertyIsRunning, kAudioProcessPropertyIsRunningOutput]
        for o in now.subtracting(watchedProcesses) {
            for sel in selectors {
                var a = Audio.address(sel)
                AudioObjectAddPropertyListenerBlock(o, &a, DispatchQueue.main, block)
            }
        }
        for o in watchedProcesses.subtracting(now) {
            for sel in selectors {
                var a = Audio.address(sel)
                AudioObjectRemovePropertyListenerBlock(o, &a, DispatchQueue.main, block)
            }
        }
        watchedProcesses = now
    }

    /// Creates the strip's tap and starts its engine. The tap stays for as long as the strip exists.
    private func rebuildTap(_ s: Strip) {
        s.engine?.stop()
        s.engineKey = nil
        s.slot = nil
        destroyTap(s)
        let made = Audio.makeTap(processes: s.processes, name: Engine.tapNamePrefix + " " + s.uid)
        s.tapID = made?.id ?? 0
        s.tapDescription = made?.description
        s.error = made == nil ? "Could not tap \(s.displayName)." : nil
        s.lastTapAudio = Date()
        reconcileApp(s, force: true)
    }

    /// The app gained or lost a process object: change the live tap in place. Rebuild only this app's engine if that fails.
    private func updateTap(_ s: Strip, _ processes: [AudioObjectID]) {
        s.processes = processes
        guard s.tapID != 0, let desc = s.tapDescription else { rebuildTap(s); return }
        if !Audio.setTapProcesses(s.tapID, desc, processes) { rebuildTap(s) }
    }

    /// Stops the engine, then destroys the tap: the app's normal audio returns.
    private func stopApp(_ s: Strip) {
        s.engine?.stop()
        s.engineKey = nil
        s.slot = nil
        destroyTap(s)
    }

    private func destroyTap(_ s: Strip) {
        if s.tapID != 0 { AudioHardwareDestroyProcessTap(s.tapID) }
        s.tapID = 0
        s.tapDescription = nil
    }

    /// Rebuilds every app engine whose key changed (new default output).
    private func reconcileApps() {
        for s in apps { reconcileApp(s) }
    }

    private func reconcileApp(_ s: Strip, force: Bool = false) {
        guard let engine = s.engine else { return }
        var key: EngineKey?
        let out = Audio.defaultOutput()
        if s.tapID != 0, let tapUID = s.tapDescription?.uuid.uuidString, out != 0,
           let outUID = Audio.string(out, kAudioDevicePropertyDeviceUID) {
            // Drift compensation on, except for Bluetooth outputs (reported crackle).
            key = EngineKey(output: EngineDevice(uid: outUID, id: out), members: [],
                            taps: [EngineTap(uid: tapUID, drift: !Audio.isBluetooth(out))])
        }
        guard force || key != s.engineKey else { return }
        s.engineKey = key   // set before starting: our own aggregate fires a device list change
        s.slot = nil
        guard let key else {
            engine.stop()
            if s.tapID != 0 { s.error = "No output device." }
            return
        }
        s.error = engine.start(key: key, targets: [target(s)])
        if s.error == nil { s.slot = 0 }
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

    /// ponytail: the Screen & System Audio Recording pane. Unverified that this anchor lands on the audio part on macOS 27.
    func openAudioCaptureSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}

// Snapshot fixtures only (scripts/snapshot.swift).
extension Mixer {
    static func fixtureStrip(uid: String, name: String, isApp: Bool = false, connected: Bool = true, position: Float = 0.5,
                             trimDB: Float = 0, muted: Bool = false, needleDB: Float = Mixer.needleFloorDB, clip: Float = 0,
                             noSignal: Bool = false, isDefaultInput: Bool = false, deviceGain: Float? = nil,
                             icon: NSImage? = nil, error: String? = nil) -> Strip {
        let s = Strip(uid: uid, deviceName: name, saved: nil, isApp: isApp)
        s.connected = connected; s.position = position; s.trimDB = trimDB; s.muted = muted; s.needleDB = needleDB
        s.clip = clip; s.noSignal = noSignal; s.isDefaultInput = isDefaultInput; s.deviceGain = deviceGain
        s.icon = icon; s.error = error
        return s
    }

    func fixture(strips: [Strip], apps: [Strip], micDenied: Bool = false, captureMaybeOff: Bool = false) {
        self.strips = strips; self.apps = apps; self.micDenied = micDenied; self.captureMaybeOff = captureMaybeOff
    }
}
