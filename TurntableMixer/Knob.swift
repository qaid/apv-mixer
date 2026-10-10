import SwiftUI
import AppKit

/// One rotary knob for every control. `fraction` is the pointer position, 0...1 over a 300° sweep
/// (7 o'clock to 5 o'clock). Drag up/down or scroll to turn; double-click resets.
struct Knob: View {
    enum Style { case chrome, small }

    let style: Style
    let fraction: Float
    /// Tick dot positions (0...1) drawn around a chrome knob.
    var ticks: [Float] = []
    /// Tick that is drawn larger (for example the 0 dB mark).
    var bigTick: Float?
    var enabled = true
    let label: String
    let valueText: String
    /// Receives the requested fraction, already clamped to 0...1.
    let set: (Float) -> Void
    var reset: (() -> Void)?

    static let sweep: Double = 300
    private static let dragPoints: Float = 200
    private static let scrollPoints: Float = 400
    private static let step: Float = 0.05

    @State private var dragStart: Float?

    private var diameter: CGFloat { style == .chrome ? 76 : 38 }
    private var ringRadius: CGFloat { diameter / 2 + 14 }
    private var frameSize: CGFloat { style == .chrome ? ringRadius * 2 + 10 : diameter + 6 }

    private func angle(_ f: Float) -> Double { -Knob.sweep / 2 + Knob.sweep * Double(f) }

    var body: some View {
        ZStack {
            ForEach(ticks, id: \.self) { tick in
                let big = tick == bigTick
                let a = angle(tick) * .pi / 180
                Circle()
                    .fill(tick <= fraction ? Color.orange : Color(white: 0.5).opacity(0.8))
                    .frame(width: big ? 7 : 4.5, height: big ? 7 : 4.5)
                    .offset(x: ringRadius * CGFloat(sin(a)), y: -ringRadius * CGFloat(cos(a)))
            }
            body(of: style)
        }
        .frame(width: frameSize, height: frameSize)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 2).onChanged { drag in
            let start = dragStart ?? fraction
            dragStart = start
            set(Self.clamp(start - Float(drag.translation.height) / Self.dragPoints))
        }.onEnded { _ in dragStart = nil })
        .onTapGesture(count: 2) { reset?() }
        .background(ScrollCatcher(enabled: enabled) { dy in
            set(Self.clamp(fraction + Float(dy) / Self.scrollPoints))
        })
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(Self.clamp(fraction + Self.step))
            case .decrement: set(Self.clamp(fraction - Self.step))
            @unknown default: break
            }
        }
    }

    private static func clamp(_ f: Float) -> Float { min(max(f, 0), 1) }

    @ViewBuilder private func body(of style: Style) -> some View {
        switch style {
        case .chrome:
            ZStack {
                Circle().fill(.black.opacity(0.35)).frame(width: diameter + 6).blur(radius: 4).offset(y: 3)
                Circle().fill(AngularGradient(colors: Self.chromeColors, center: .center, angle: .degrees(-40)))
                    .frame(width: diameter, height: diameter)
                Circle().stroke(.black.opacity(0.55), lineWidth: 1).frame(width: diameter, height: diameter)
                Circle().fill(RadialGradient(colors: [Color(white: 0.96), Color(white: 0.62)],
                                             center: .init(x: 0.38, y: 0.3), startRadius: 0, endRadius: diameter * 0.45))
                    .frame(width: diameter * 0.68, height: diameter * 0.68)
                Circle().stroke(.white.opacity(0.6), lineWidth: 0.75).frame(width: diameter * 0.68)
                pointer(color: Color(white: 0.1), width: 2.5)
            }
        case .small:
            ZStack {
                Circle().fill(.black.opacity(0.35)).frame(width: diameter + 2).blur(radius: 2).offset(y: 2)
                Circle().fill(LinearGradient(colors: [Color(white: 0.28), Color(white: 0.04)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: diameter, height: diameter)
                Circle().stroke(.white.opacity(0.22), lineWidth: 1).frame(width: diameter - 1)
                pointer(color: .white, width: 2)
            }
        }
    }

    /// A line from the knob's rim toward the centre, turned to the current angle.
    private func pointer(color: Color, width: CGFloat) -> some View {
        Capsule().fill(color)
            .frame(width: width, height: diameter * 0.3)
            .offset(y: -diameter * 0.3)
            .rotationEffect(.degrees(angle(fraction)))
    }

    private static let chromeColors: [Color] = [
        Color(white: 0.95), Color(white: 0.55), Color(white: 0.9), Color(white: 0.4),
        Color(white: 0.96), Color(white: 0.5), Color(white: 0.88), Color(white: 0.45), Color(white: 0.95),
    ]
}

/// Passes vertical scroll-wheel and trackpad scrolling over its bounds to `onScroll`.
/// It never takes clicks, so the knob's own gestures still work.
private struct ScrollCatcher: NSViewRepresentable {
    let enabled: Bool
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.enabled = enabled
        view.onScroll = onScroll
    }

    static func dismantleNSView(_ view: CatcherView, coordinator: ()) { view.removeMonitor() }

    final class CatcherView: NSView {
        var enabled = true
        var onScroll: (CGFloat) -> Void = { _ in }
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.enabled, event.window === self.window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
                self.onScroll(dy)
                return nil
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
