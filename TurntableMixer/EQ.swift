import Foundation

/// Bass and Treble: two shelving filters per strip (RBJ Audio EQ Cookbook, shelf slope 1). Foundation only.
nonisolated enum EQ {
    static let rangeDB: Float = 12          // each knob runs -12...+12 dB
    static let bassHz: Float = 100
    static let trebleHz: Float = 8000
    static let stepDB: Float = 1            // most dB change per buffer, so a knob drag does not jump

    static func lowShelf(db: Float, rate: Float) -> Biquad { shelf(db: db, hz: bassHz, rate: rate, high: false) }
    static func highShelf(db: Float, rate: Float) -> Biquad { shelf(db: db, hz: trebleHz, rate: rate, high: true) }

    private static func shelf(db: Float, hz: Float, rate: Float, high: Bool) -> Biquad {
        if db == 0 { return .identity }
        let a = powf(10, db / 40)
        let w = 2 * Float.pi * min(hz, rate * 0.45) / rate
        let c = cosf(w)
        let alpha2 = sinf(w) * sqrtf(2) * sqrtf(a)    // 2 * sqrt(A) * alpha, with alpha = sin(w) / 2 * sqrt(2)
        let s: Float = high ? -1 : 1                  // the high shelf is the low shelf with the cosine terms' sign flipped
        let b0 = a * ((a + 1) - s * (a - 1) * c + alpha2)
        let b1 = 2 * s * a * ((a - 1) - s * (a + 1) * c)
        let b2 = a * ((a + 1) - s * (a - 1) * c - alpha2)
        let a0 = (a + 1) + s * (a - 1) * c + alpha2
        let a1 = -2 * s * ((a - 1) + s * (a + 1) * c)
        let a2 = (a + 1) + s * (a - 1) * c - alpha2
        return Biquad(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    /// Moves `current` toward `target` by at most `stepDB`.
    static func stepped(_ current: Float, to target: Float) -> Float {
        current < target ? min(current + stepDB, target) : max(current - stepDB, target)
    }
}

/// Normalized biquad coefficients (a0 = 1).
nonisolated struct Biquad {
    var b0: Float, b1: Float, b2: Float, a1: Float, a2: Float
    static let identity = Biquad(b0: 1, b1: 0, b2: 0, a1: 0, a2: 0)

    /// Gain magnitude at `hz` (for checks).
    func gain(at hz: Float, rate: Float) -> Float {
        let w = 2 * Double.pi * Double(hz / rate)
        let (c1, s1, c2, s2) = (cos(w), -sin(w), cos(2 * w), -sin(2 * w))
        let nr = Double(b0) + Double(b1) * c1 + Double(b2) * c2, ni = Double(b1) * s1 + Double(b2) * s2
        let dr = 1 + Double(a1) * c1 + Double(a2) * c2, di = Double(a1) * s1 + Double(a2) * s2
        return Float(sqrt((nr * nr + ni * ni) / (dr * dr + di * di)))
    }
}

/// One channel's filter memory (transposed direct form II).
nonisolated struct BiquadState {
    var z1: Float = 0, z2: Float = 0

    mutating func process(_ x: Float, _ c: Biquad) -> Float {
        let y = c.b0 * x + z1
        z1 = c.b1 * x - c.a1 * y + z2
        z2 = c.b2 * x - c.a2 * y
        return y
    }
}
