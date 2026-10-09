import Foundation

/// Fader math. Slider position 0...1 <-> dB <-> linear gain. Foundation only.
/// Position 0 is -inf (silence). Above 0, the slider runs from -60 dB up to 0 dB at `detent`,
/// then up to +10 dB at position 1.
nonisolated enum Gain {
    static let floorDB: Float = -60
    static let maxDB: Float = 10
    static let detent: Float = 0.75      // slider position of 0 dB
    static let snapZone: Float = 0.02    // positions this close to the detent snap onto it

    static func db(at position: Float) -> Float {
        let p = min(max(position, 0), 1)
        if p <= 0 { return -Float.infinity }
        if p <= detent { return floorDB + (0 - floorDB) * p / detent }
        return maxDB * (p - detent) / (1 - detent)
    }

    static func position(db: Float) -> Float {
        if db <= floorDB { return 0 }
        if db <= 0 { return detent * (db - floorDB) / (0 - floorDB) }
        return min(detent + (1 - detent) * db / maxDB, 1)
    }

    static func linear(db: Float) -> Float {
        db == -Float.infinity ? 0 : powf(10, db / 20)
    }

    static func linear(at position: Float) -> Float { linear(db: db(at: position)) }

    /// Pulls a dragged position onto the 0 dB detent when it is close.
    static func snapped(_ position: Float) -> Float {
        let p = min(max(position, 0), 1)
        return abs(p - detent) < snapZone ? detent : p
    }

    static func label(db: Float) -> String {
        db == -Float.infinity ? "-∞ dB" : String(format: "%+.1f dB", db)
    }
}
