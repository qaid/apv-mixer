import SwiftUI

/// Backlit analog VU meter. `needleDB` is dBFS with ballistics already applied by the model.
struct VUMeter: View {
    let needleDB: Float
    /// Clip light level 0...1 (lit while the strip clips, then fading out).
    var clip: Float = 0

    /// Calibration: 0 VU = this level in dBFS.
    static let vuZeroDBFS: Float = -12

    private static let size = CGSize(width: 132, height: 78)
    private static let pivot = CGPoint(x: 66, y: 78 + 28)
    private static let radius: CGFloat = 80
    private static let halfSweep: Double = 40
    private static let majors: [Float] = [-20, -10, -7, -5, -3, -1, 0, 1, 2, 3]
    private static let minors: [Float] = [-9, -8, -6, -4, -2]

    /// Scale position 0...1 for a VU value. Real VU scales are linear in amplitude, -20 VU = 0.
    static func fraction(vu: Float) -> Double {
        let v = min(max(vu, -20), 3)
        let low = pow(10.0, -20.0 / 20), high = pow(10.0, 3.0 / 20)
        return (pow(10.0, Double(v) / 20) - low) / (high - low)
    }

    private static func angle(vu: Float) -> Double { -halfSweep + 2 * halfSweep * fraction(vu: vu) }

    private static func point(angle: Double, radius: CGFloat) -> CGPoint {
        let a = angle * .pi / 180
        return CGPoint(x: pivot.x + radius * CGFloat(sin(a)), y: pivot.y - radius * CGFloat(cos(a)))
    }

    private var needleAngle: Double {
        needleDB <= -60 ? -Self.halfSweep : Self.angle(vu: needleDB - Self.vuZeroDBFS)
    }

    var body: some View {
        let face = RoundedRectangle(cornerRadius: 5)
        ZStack {
            face.fill(RadialGradient(colors: [Color(red: 1.0, green: 0.93, blue: 0.72),
                                              Color(red: 0.93, green: 0.80, blue: 0.52),
                                              Color(red: 0.74, green: 0.58, blue: 0.32)],
                                     center: .init(x: 0.5, y: 0.7), startRadius: 4, endRadius: 100))
            Canvas { context, _ in drawScale(&context) }
            Needle(angle: needleAngle)
                .stroke(Color(white: 0.04), lineWidth: 1.2)
                .animation(.linear(duration: 1.0 / 30), value: needleAngle)
            clipLight
            LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center)
            // Black plate hides the pivot at the bottom edge.
            Rectangle().fill(Color(white: 0.06)).frame(height: 5)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(face)
        .overlay(face.stroke(LinearGradient(colors: [.black.opacity(0.9), .black.opacity(0.5)],
                                            startPoint: .top, endPoint: .bottom), lineWidth: 2.5))
        .overlay(face.inset(by: 2.5).stroke(.black.opacity(0.35), lineWidth: 2).blur(radius: 1.5).clipShape(face))
        .shadow(color: Color(red: 1, green: 0.7, blue: 0.3).opacity(0.45), radius: 9)
        .accessibilityElement()
        .accessibilityLabel("Level meter")
        .accessibilityValue(String(format: "%.0f dBFS", needleDB) + ", clip light " + (clip > 0 ? "lit" : "off"))
    }

    /// A small red lens in the upper-left corner, under the glass highlight. Off: dark red, still visible on the cream face.
    private var clipLight: some View {
        let level = Double(min(max(clip, 0), 1))
        let off = (r: 0.42, g: 0.08, b: 0.07), on = (r: 1.0, g: 0.25, b: 0.18)
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * level }
        return ZStack(alignment: .leading) {
            Text("CLIP").font(.custom("Avenir Next Condensed", size: 6.5).weight(.bold)).tracking(0.6)
                .foregroundStyle(Color(white: 0.06)).offset(x: 11)
            Circle()
                .fill(RadialGradient(colors: [Color(red: mix(0.55, 1.0), green: mix(0.15, 0.4), blue: mix(0.12, 0.3)),
                                              Color(red: mix(off.r, on.r), green: mix(off.g, on.g), blue: mix(off.b, on.b))],
                                     center: .init(x: 0.4, y: 0.35), startRadius: 0, endRadius: 5))
                .frame(width: 7, height: 7)
                .overlay(Circle().stroke(.black.opacity(0.55), lineWidth: 0.75))
                .shadow(color: .red.opacity(0.9 * level), radius: 4 * level)
        }
        .fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, 8).padding(.top, 8)
        .accessibilityHidden(true)
    }

    private func drawScale(_ context: inout GraphicsContext) {
        let ink = Color(white: 0.06)
        let zero = Self.angle(vu: 0), end = Self.angle(vu: 3)
        context.stroke(arc(from: zero, to: end, radius: Self.radius - 2), with: .color(Color(red: 0.8, green: 0.1, blue: 0.08)), lineWidth: 4)
        context.stroke(arc(from: -Self.halfSweep, to: Self.halfSweep, radius: Self.radius), with: .color(ink), lineWidth: 1)
        for vu in Self.majors {
            let a = Self.angle(vu: vu)
            var tick = Path()
            tick.move(to: Self.point(angle: a, radius: Self.radius - 5))
            tick.addLine(to: Self.point(angle: a, radius: Self.radius + 1))
            context.stroke(tick, with: .color(ink), lineWidth: 1.1)
            let text = vu > 0 ? "+\(Int(vu))" : "\(Int(vu))"
            context.draw(Text(text).font(.system(size: 6.5, weight: .bold)).foregroundColor(vu >= 0 ? Color(red: 0.7, green: 0.05, blue: 0.05) : ink),
                         at: Self.point(angle: a, radius: Self.radius + 8))
        }
        for vu in Self.minors {
            var tick = Path()
            tick.move(to: Self.point(angle: Self.angle(vu: vu), radius: Self.radius - 3))
            tick.addLine(to: Self.point(angle: Self.angle(vu: vu), radius: Self.radius))
            context.stroke(tick, with: .color(ink), lineWidth: 0.7)
        }
        context.draw(Text("VU").font(.custom("Avenir Next Condensed", size: 11).weight(.bold)).foregroundColor(ink),
                     at: CGPoint(x: Self.size.width / 2, y: Self.size.height - 18))
    }

    private func arc(from: Double, to: Double, radius: CGFloat) -> Path {
        var path = Path()
        let steps = 48
        for i in 0...steps {
            let p = Self.point(angle: from + (to - from) * Double(i) / Double(steps), radius: radius)
            i == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        return path
    }

    /// The needle: a line from the pivot (below the face) at `angle` degrees from vertical.
    private struct Needle: Shape {
        var angle: Double
        var animatableData: Double {
            get { angle }
            set { angle = newValue }
        }
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: VUMeter.pivot)
            path.addLine(to: VUMeter.point(angle: angle, radius: VUMeter.radius + 3))
            return path
        }
    }
}
