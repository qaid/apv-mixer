import SwiftUI

/// The turntable's input strip (P1: plain styling; DJ styling is P2).
struct StripView: View {
    let mixer: Mixer
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 10) {
            nameView
            if mixer.noSignal && mixer.connected {
                Text("No signal").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 6) {
                    ClipLight(lit: mixer.clipLit) { mixer.clearClip() }
                    MeterView(left: mixer.levelL, right: mixer.levelR)
                }
                FaderView(position: Binding(get: { mixer.position }, set: { mixer.setPosition($0) }))
            }
            Text(Gain.label(db: mixer.db))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.white)
            Button(mixer.muted ? "Muted" : "Mute") { mixer.toggleMute() }
                .tint(mixer.muted ? .red : nil)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            if let error = mixer.engineError, mixer.connected {
                Text(error).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
            if !mixer.connected {
                Text("Disconnected").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 150)
        .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 8))
        .opacity(mixer.connected ? 1 : 0.4)
        .disabled(!mixer.connected)
    }

    @ViewBuilder private var nameView: some View {
        if editing {
            TextField("Name", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { mixer.rename(draft); editing = false }
                .onExitCommand { editing = false }
        } else {
            Text(mixer.displayName)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .onTapGesture(count: 2) { draft = mixer.displayName; editing = true }
        }
    }
}

struct ClipLight: View {
    let lit: Bool
    let reset: () -> Void
    var body: some View {
        Button(action: reset) {
            Circle().fill(lit ? Color.red : Color(white: 0.25)).frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .help("Clip light. Click to clear.")
    }
}

/// Stereo peak meter, segmented green / yellow / red. Reads post-fader peaks.
struct MeterView: View {
    let left: Float
    let right: Float
    private static let segments = 24            // 2 dB each, -48 dB to 0 dB

    var body: some View {
        HStack(spacing: 3) {
            bar(left)
            bar(right)
        }
        .frame(height: 260)
    }

    private func bar(_ level: Float) -> some View {
        let db = level > 0 ? 20 * log10(level) : -Float.infinity
        return VStack(spacing: 2) {
            ForEach((0..<Self.segments).reversed(), id: \.self) { i in
                let threshold = -48 + Float(i) * 2
                Rectangle()
                    .fill(db > threshold ? color(threshold) : Color(white: 0.2))
                    .frame(width: 10)
            }
        }
    }

    private func color(_ threshold: Float) -> Color {
        threshold < -12 ? .green : (threshold < -4 ? .yellow : .red)
    }
}

/// Vertical fader. Drag to move; snaps to 0 dB; double-click resets to 0 dB.
struct FaderView: View {
    @Binding var position: Float
    private let capHeight: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            let travel = geo.size.height - capHeight
            ZStack(alignment: .top) {
                Capsule().fill(Color(white: 0.05)).frame(width: 6).frame(maxWidth: .infinity)
                Rectangle().fill(Color.white.opacity(0.5)).frame(width: 30, height: 1)
                    .offset(y: capHeight / 2 + travel * CGFloat(1 - Gain.detent))
                    .frame(maxWidth: .infinity)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(white: 0.8))
                    .frame(width: 34, height: capHeight)
                    .offset(y: travel * CGFloat(1 - position))
                    .frame(maxWidth: .infinity)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 1).onChanged { drag in
                let p = 1 - (drag.location.y - capHeight / 2) / travel
                position = Gain.snapped(Float(min(max(p, 0), 1)))
            })
            .onTapGesture(count: 2) { position = Gain.detent }
        }
        .frame(width: 44, height: 286)
    }
}
