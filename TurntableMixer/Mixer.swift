import AppKit
import AVFoundation
import CoreAudio
import Observation

/// Mixer state for P1: one input strip, for the turntable. Main thread only.
@Observable final class Mixer {
    static let shared = Mixer()

    // Turntable strip
    private(set) var turntableUID: String?
    private(set) var connected = false
    private(set) var deviceName: String?
    private(set) var savedName: String?
    private(set) var engineError: String?
    private(set) var levelL: Float = 0
    private(set) var levelR: Float = 0
    private(set) var clipLit = false
    private(set) var noSignal = false
    // Fader and mute live in memory by UID; persisting them is P2.
    private var faders: [String: Float] = [:]
    private var mutes: [String: Bool] = [:]

    // Microphone permission
    private(set) var micDenied = false

    @ObservationIgnored private let engine = Engine()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var lastLoud = Date()
    @ObservationIgnored private var lastMicStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @ObservationIgnored private var deviceListener: AudioObjectPropertyListenerBlock?

    private static let inputDevicesKey = "inputDevices"
    // ponytail: P1 knows one name; P2 (strips for all hardware inputs) removes this rule.
    private static let turntableName = "USB AUDIO  CODEC"
    // Raw input below this for `noSignalSeconds` means the turntable is off (measured: off peaks about -78 dBFS, on with needle up peaks above -72 dBFS). Calibration knob.
    static let noSignalDB: Float = -75
    static let noSignalSeconds = 3.0

    var displayName: String { savedName ?? deviceName ?? "Turntable" }
    var position: Float { turntableUID.flatMap { faders[$0] } ?? 0 }   // D4: new devices start silent
    var muted: Bool { turntableUID.flatMap { mutes[$0] } ?? false }
    var db: Float { Gain.db(at: position) }

    func start() {
        guard !started else { return }
        started = true

        updateMicStatus()
        if lastMicStatus == .notDetermined {
            Task { _ = await AVCaptureDevice.requestAccess(for: .audio); self.updateMicStatus() }
        }

        var address = Audio.address(kAudioHardwarePropertyDevices)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        deviceListener = block
        AudioObjectAddPropertyListenerBlock(Audio.system, &address, DispatchQueue.main, block)

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

    // MARK: Turntable

    /// Called on every device list change.
    func refresh() {
        let devices = Audio.inputDevices()
        var saved = UserDefaults.standard.dictionary(forKey: Self.inputDevicesKey) as? [String: [String: Any]] ?? [:]

        // Saved UID wins. With nothing saved yet, find the turntable by name once and save its UID.
        var found = devices.first { saved[$0.uid] != nil }
        if found == nil, saved.isEmpty, let byName = devices.first(where: { $0.name == Self.turntableName }) {
            saved[byName.uid] = [:]
            UserDefaults.standard.set(saved, forKey: Self.inputDevicesKey)
            found = byName
        }
        turntableUID = found?.uid ?? saved.keys.sorted().first
        savedName = turntableUID.flatMap { saved[$0]?["name"] as? String }
        if let found { deviceName = found.name }

        guard let found else {
            connected = false
            engine.stop()
            levelL = 0; levelR = 0
            noSignal = false
            return
        }
        connected = true
        if engine.runningDeviceID != found.id {
            engineError = engine.start(turntable: found)
            lastLoud = Date()
            pushGain()
        }
    }

    func rename(_ name: String) {
        guard let uid = turntableUID else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        var saved = UserDefaults.standard.dictionary(forKey: Self.inputDevicesKey) as? [String: [String: Any]] ?? [:]
        var entry = saved[uid] ?? [:]
        if trimmed.isEmpty { entry["name"] = nil } else { entry["name"] = trimmed }
        saved[uid] = entry
        UserDefaults.standard.set(saved, forKey: Self.inputDevicesKey)
        savedName = trimmed.isEmpty ? nil : trimmed
    }

    func setPosition(_ p: Float) {
        guard let uid = turntableUID else { return }
        faders[uid] = min(max(p, 0), 1)
        pushGain()
    }

    func toggleMute() {
        guard let uid = turntableUID else { return }
        mutes[uid] = !(mutes[uid] ?? false)
        pushGain()
    }

    func clearClip() { clipLit = false }

    private func pushGain() {
        engine.setTarget(muted ? 0 : Gain.linear(at: position))
    }

    private func tick() {
        guard connected else { return }
        let p = engine.takePeaks()
        let now = Date()
        if p.input > 0, 20 * log10(p.input) >= Self.noSignalDB { lastLoud = now }
        noSignal = now.timeIntervalSince(lastLoud) > Self.noSignalSeconds
        levelL = max(p.l, levelL * 0.85)   // quick fall-off; peak hold is P2
        levelR = max(p.r, levelR * 0.85)
        if p.clipped { clipLit = true }
    }

    // MARK: Microphone permission

    func updateMicStatus() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        micDenied = status == .denied || status == .restricted
        if status == .authorized, lastMicStatus != .authorized {
            engine.stop()   // rebuild so the turntable's input starts delivering audio
            refresh()
        }
        lastMicStatus = status
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
