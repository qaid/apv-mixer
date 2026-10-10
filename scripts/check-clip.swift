// Run: swiftc TurntableMixer/ClipFade.swift scripts/check-clip.swift -o /tmp/check-clip && /tmp/check-clip
import Foundation

@main struct CheckClip {
    static func main() {
        func near(_ a: Float, _ b: Float, _ tol: Float = 1e-4) -> Bool { abs(a - b) <= tol }

        assert(ClipFade.next(current: 0, clipped: true, dt: 0.03) == 1, "a clip lights it fully")
        assert(ClipFade.next(current: 0.3, clipped: true, dt: 0.03) == 1, "clipping again keeps it full")
        assert(near(ClipFade.next(current: 1, clipped: false, dt: 0.25), 0.9), "falls 1/2.5 per second")
        assert(ClipFade.next(current: 0, clipped: false, dt: 0.03) == 0, "off stays off")
        assert(ClipFade.next(current: 0.01, clipped: false, dt: 0.2) == 0, "never below 0")

        // 2.5 s of 30 ms ticks takes full to off
        var v: Float = 1
        for _ in 0..<84 { v = ClipFade.next(current: v, clipped: false, dt: 0.03) }
        assert(v == 0, "off after 2.5 s")
        v = 1
        for _ in 0..<80 { v = ClipFade.next(current: v, clipped: false, dt: 0.03) }
        assert(v > 0, "still faintly lit just before 2.5 s")
        print("check-clip: ok")
    }
}
