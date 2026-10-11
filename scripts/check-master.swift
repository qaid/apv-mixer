// Run: swiftc TurntableMixer/Gain.swift TurntableMixer/MasterMath.swift scripts/check-master.swift -o /tmp/check-master && /tmp/check-master
import Foundation

@main struct CheckMaster {
    static func main() {
        func near(_ a: Float, _ b: Float, _ tol: Float = 1e-4) -> Bool { abs(a - b) <= tol }
        func nearD(_ a: Double, _ b: Double, _ tol: Double = 1e-6) -> Bool { abs(a - b) <= tol }

        // Hardware volume: the mixer adds no gain.
        assert(MasterMath.gain(software: false, hasMute: true, volume: 0.3, muted: false) == 1)
        assert(MasterMath.gain(software: false, hasMute: true, volume: 0.3, muted: true) == 1, "the output mutes itself")
        // Hardware volume at 0: the mixer silences the sum too.
        assert(MasterMath.gain(software: false, hasMute: true, volume: 0, muted: false) == 0)
        // Meter factor: follows volume and mute; software gain is already in the peaks.
        assert(MasterMath.meterFactor(software: false, volume: 0, muted: false) == 0)
        assert(MasterMath.meterFactor(software: false, volume: 1, muted: true) == 0)
        assert(near(MasterMath.meterFactor(software: false, volume: 1, muted: false), 1))
        assert(MasterMath.meterFactor(software: true, volume: 0.3, muted: false) == 1)
        // Hardware volume, no hardware mute: mute is software.
        assert(MasterMath.gain(software: false, hasMute: false, volume: 0.3, muted: true) == 0)
        assert(MasterMath.gain(software: false, hasMute: false, volume: 0.3, muted: false) == 1)
        // Software volume: 0 silent, 1 is 0 dB, mute wins.
        assert(MasterMath.gain(software: true, hasMute: false, volume: 0, muted: false) == 0)
        assert(near(MasterMath.gain(software: true, hasMute: false, volume: 1, muted: false), 1))
        assert(MasterMath.gain(software: true, hasMute: true, volume: 1, muted: true) == 0)
        let half = MasterMath.gain(software: true, hasMute: false, volume: 0.5, muted: false)
        assert(half > 0 && half < 1, "half is quieter than unity")

        // Latency: (48 + 256) + (96 + 256) = 656 frames at 48 kHz.
        assert(nearD(MasterMath.latencyMs(outputFrames: 48, inputFrames: 96, bufferFrames: 256, rate: 48000), 656.0 / 48))
        assert(nearD(MasterMath.latencyMs(outputFrames: 48, inputFrames: nil, bufferFrames: 256, rate: 48000), 304.0 / 48))

        // Peak hold: the highest of the last 0.5 s.
        var h = PeakHold()
        assert(h.add(0.1, at: 0) == 0.1)
        assert(h.add(0.4, at: 0.1) == 0.4)
        assert(h.add(0.2, at: 0.3) == 0.4, "peak still held")
        assert(h.add(0.2, at: 0.7) == 0.2, "peak aged out after 0.5 s")
        assert(h.add(0, at: 1.3) == 0)
        print("check-master: ok")
    }
}
