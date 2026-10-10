import SwiftUI

/// Panel colours and lettering. Light appearance = brushed silver, Dark = brushed black.
enum Panel {
    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.80) : Color(white: 0.14)
    }
    static func dimInk(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.55) : Color(white: 0.38)
    }
}

/// Engraved small-caps lettering: a 1 pt highlight (or shadow) below the ink.
struct Engraved: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var size: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .font(.custom("Avenir Next Condensed", size: size).weight(.semibold))
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(Panel.ink(scheme))
            .shadow(color: scheme == .dark ? .black.opacity(0.9) : .white.opacity(0.8),
                    radius: 0, x: 0, y: scheme == .dark ? -1 : 1)
    }
}

extension View {
    func engraved(size: CGFloat = 10) -> some View { modifier(Engraved(size: size)) }
}

/// The brushed-metal window background with corner screws.
struct Faceplate: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            LinearGradient(stops: scheme == .dark ? Self.blackStops : Self.silverStops,
                           startPoint: .leading, endPoint: .trailing)
            Canvas { context, size in
                var rng = SeededRandom(seed: 7)
                var y: CGFloat = 0
                while y < size.height {
                    let x0 = CGFloat(rng.next()) * size.width * 0.6
                    let length = size.width * (0.2 + CGFloat(rng.next()) * 0.8)
                    let alpha = 0.015 + rng.next() * 0.06
                    let light = rng.next() > 0.5
                    var path = Path()
                    path.move(to: CGPoint(x: x0, y: y))
                    path.addLine(to: CGPoint(x: x0 + length, y: y))
                    let tone: Color = (light != (scheme == .dark)) ? .white : .black
                    context.stroke(path, with: .color(tone.opacity(alpha)), lineWidth: 0.6)
                    y += 0.9
                }
            }
            LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.04 : 0.18), .clear,
                                    .black.opacity(scheme == .dark ? 0.3 : 0.08)],
                           startPoint: .top, endPoint: .bottom)
        }
        .overlay(alignment: .topLeading) { ScrewHead().padding(8) }
        .overlay(alignment: .topTrailing) { ScrewHead().padding(8) }
        .overlay(alignment: .bottomLeading) { ScrewHead().padding(8) }
        .overlay(alignment: .bottomTrailing) { ScrewHead().padding(8) }
        .ignoresSafeArea()
    }

    private static let silverStops: [Gradient.Stop] = [
        .init(color: Color(white: 0.78), location: 0), .init(color: Color(white: 0.90), location: 0.18),
        .init(color: Color(white: 0.82), location: 0.4), .init(color: Color(white: 0.92), location: 0.62),
        .init(color: Color(white: 0.80), location: 0.82), .init(color: Color(white: 0.88), location: 1),
    ]
    private static let blackStops: [Gradient.Stop] = [
        .init(color: Color(white: 0.09), location: 0), .init(color: Color(white: 0.17), location: 0.18),
        .init(color: Color(white: 0.11), location: 0.4), .init(color: Color(white: 0.18), location: 0.62),
        .init(color: Color(white: 0.10), location: 0.82), .init(color: Color(white: 0.15), location: 1),
    ]
}

/// Small deterministic generator so the brushing does not shimmer on redraw.
private struct SeededRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

/// A slotted screw head.
struct ScrewHead: View {
    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(white: 0.85), Color(white: 0.42)],
                                 center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 8))
            .overlay(Circle().stroke(.black.opacity(0.45), lineWidth: 0.75))
            .overlay(Rectangle().fill(.black.opacity(0.6)).frame(width: 7, height: 1.2).rotationEffect(.degrees(35)))
            .frame(width: 9, height: 9)
            .shadow(color: .black.opacity(0.4), radius: 0.5, y: 0.5)
    }
}

/// A thin engraved line between strips.
struct PanelDivider: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(.black.opacity(scheme == .dark ? 0.8 : 0.28)).frame(width: 1)
            Rectangle().fill(.white.opacity(scheme == .dark ? 0.08 : 0.7)).frame(width: 1)
        }
    }
}

/// A heavier engraved line between the Inputs group and the Apps group.
struct GroupDivider: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(.black.opacity(scheme == .dark ? 0.9 : 0.4)).frame(width: 3)
            Rectangle().fill(.white.opacity(scheme == .dark ? 0.1 : 0.8)).frame(width: 1)
        }
        .padding(.horizontal, 12)
        .padding(.top, 48)   // starts and ends with the thin strip dividers, below the group titles
    }
}
