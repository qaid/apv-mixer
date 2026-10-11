import Foundation

/// Pure rules for the master strip and status line (spec D8, §6). Foundation only.
nonisolated enum MasterMath {
    /// The gain the mixer applies to the sum. Software volume: the knob maps through the strips' scale (1 = 0 dB, 0 = silence).
    /// Mute is applied here when the mixer owns it: software volume, or an output with no mute of its own.
    /// At volume 0 the mixer also silences the sum: some outputs still play quietly at their lowest volume.
    static func gain(software: Bool, hasMute: Bool, volume: Float, muted: Bool) -> Float {
        if muted && (software || !hasMute) { return 0 }
        return software || volume <= 0 ? curve(volume) : 1
    }

    /// What the master needle multiplies the mix by, so it follows the master volume and mute.
    /// The software gain is already in the engines' peaks; a system volume is estimated with the same curve.
    static func meterFactor(software: Bool, volume: Float, muted: Bool) -> Float {
        muted ? 0 : software ? 1 : curve(volume)
    }

    /// Knob 0...1 through the strips' scale: 0 = silence, 1 = 0 dB.
    private static func curve(_ volume: Float) -> Float { Gain.linear(at: min(max(volume, 0), 1) * Gain.detent) }

    /// Turntable to speaker estimate in ms. `input` is the largest member input-scope latency, nil when the input engine has no members.
    static func latencyMs(outputFrames: UInt32, inputFrames: UInt32?, bufferFrames: UInt32, rate: Double) -> Double {
        guard rate > 0 else { return 0 }
        var frames = Double(outputFrames) + Double(bufferFrames)
        if let inputFrames { frames += Double(inputFrames) + Double(bufferFrames) }
        return frames / rate * 1000
    }
}

/// The highest value seen in the last `window` seconds.
nonisolated struct PeakHold {
    let window: Double
    private var samples: [(t: Double, v: Float)] = []

    init(window: Double = 0.5) { self.window = window }

    mutating func add(_ v: Float, at t: Double) -> Float {
        samples.append((t, v))
        samples.removeAll { t - $0.t > window }
        return samples.reduce(0) { max($0, $1.v) }
    }
}
