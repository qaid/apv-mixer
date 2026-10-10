// Run: swiftc TurntableMixer/Gain.swift scripts/check-gain.swift -o /tmp/check-gain && /tmp/check-gain
import Foundation

@main struct CheckGain {
    static func main() {
        func near(_ a: Float, _ b: Float, _ tol: Float = 1e-4) -> Bool { abs(a - b) <= tol }

        assert(Gain.db(at: 0) == -Float.infinity, "bottom is -inf")
        assert(Gain.linear(at: 0) == 0, "bottom is silence")
        assert(near(Gain.db(at: Gain.detent), 0), "detent is 0 dB")
        assert(near(Gain.linear(at: Gain.detent), 1), "detent is unity")
        assert(near(Gain.db(at: 1), 10), "top is +10 dB")
        assert(near(Gain.linear(db: 10), 3.1622777, 1e-4))
        assert(near(Gain.linear(db: -20), 0.1, 1e-5))

        // monotonic
        var last = Gain.db(at: 0)
        for i in 1...1000 {
            let d = Gain.db(at: Float(i) / 1000)
            assert(d > last, "db rises with position")
            last = d
        }
        // round trip
        for db: Float in [-59, -40, -12, -3, 0, 0.5, 3, 9.9, 10] {
            assert(near(Gain.db(at: Gain.position(db: db)), db, 1e-3), "round trip \(db)")
        }
        assert(Gain.position(db: -Float.infinity) == 0)
        assert(Gain.position(db: -100) == 0)
        assert(Gain.position(db: 20) == 1)

        // detent snap
        assert(Gain.snapped(Gain.detent + 0.01) == Gain.detent)
        assert(Gain.snapped(Gain.detent - 0.01) == Gain.detent)
        assert(Gain.snapped(Gain.detent + 0.05) == Gain.detent + 0.05)
        assert(Gain.snapped(-1) == 0 && Gain.snapped(2) == 1)

        // ramp step: a small and a large change both take the same number of samples
        assert(near(Gain.rampStep(from: 0, to: 1, rampSamples: 720), 1.0 / 720, 1e-9))
        assert(near(Gain.rampStep(from: 0.5, to: 0.6, rampSamples: 100), 0.001, 1e-9))
        assert(Gain.rampStep(from: 1, to: 1, rampSamples: 720) == 0)

        assert(Gain.label(db: -Float.infinity) == "-∞ dB")
        assert(Gain.label(db: 0) == "+0.0 dB")
        print("check-gain: all checks passed")
    }
}
