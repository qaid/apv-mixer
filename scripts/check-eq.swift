// Run: swiftc TurntableMixer/EQ.swift scripts/check-eq.swift -o /tmp/check-eq && /tmp/check-eq
import Foundation

@main struct CheckEQ {
    static func main() {
        func near(_ a: Float, _ b: Float, _ tol: Float = 0.02) -> Bool { abs(a - b) <= tol }
        let rate: Float = 48000
        let six = powf(10, 6.0 / 20)

        // 0 dB is the identity.
        let flat = EQ.lowShelf(db: 0, rate: rate)
        assert(flat.b0 == 1 && flat.b1 == 0 && flat.b2 == 0 && flat.a1 == 0 && flat.a2 == 0)

        // Bass +6: lows up 6 dB, highs untouched. Bass -6: lows down.
        let bass = EQ.lowShelf(db: 6, rate: rate)
        assert(near(bass.gain(at: 10, rate: rate), six), "bass DC \(bass.gain(at: 10, rate: rate))")
        assert(near(bass.gain(at: 10000, rate: rate), 1))
        assert(near(EQ.lowShelf(db: -6, rate: rate).gain(at: 10, rate: rate), 1 / six))

        // Treble +6: highs up 6 dB, lows untouched.
        let treble = EQ.highShelf(db: 6, rate: rate)
        assert(near(treble.gain(at: 23000, rate: rate), six), "treble top \(treble.gain(at: 23000, rate: rate))")
        assert(near(treble.gain(at: 50, rate: rate), 1))

        // Half gain at the corner frequency.
        assert(near(EQ.lowShelf(db: 12, rate: rate).gain(at: EQ.bassHz, rate: rate), powf(10, 6.0 / 20), 0.05))

        // Filtering settles to the DC gain, and a boost at 44.1 kHz stays stable.
        var st = BiquadState()
        var y: Float = 0
        for _ in 0..<48000 { y = st.process(1, bass) }
        assert(near(y, six))
        var st2 = BiquadState()
        for _ in 0..<44100 { y = st2.process(1, EQ.lowShelf(db: 12, rate: 44100)) }
        assert(near(y, powf(10, 12.0 / 20), 0.05))

        // The knob value steps 1 dB per buffer toward its target.
        assert(EQ.stepped(0, to: 5) == 1 && EQ.stepped(0, to: -0.5) == -0.5 && EQ.stepped(3, to: 3) == 3)

        print("check-eq: ok")
    }
}
