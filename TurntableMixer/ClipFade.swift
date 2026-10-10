import Foundation

/// The clip light's level (0...1): full while the strip clips, then a linear fade to 0 over `seconds`.
nonisolated enum ClipFade {
    static let seconds: Float = 2.5

    static func next(current: Float, clipped: Bool, dt: Float) -> Float {
        clipped ? 1 : max(0, current - dt / seconds)
    }
}
