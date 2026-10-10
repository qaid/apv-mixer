import SwiftUI

/// One input strip, top to bottom: name, Default input, Device gain and Trim, meter, Mute, Level.
struct StripView: View {
    let mixer: Mixer
    let strip: Strip
    @Environment(\.colorScheme) private var scheme
    @State private var editing = false
    @State private var draft = ""

    static let width: CGFloat = 176

    var body: some View {
        VStack(spacing: 12) {
            nameView
            defaultButton
            HStack(spacing: 6) {
                labelled("Device gain") { deviceGainKnob }
                labelled("Trim") { trimKnob }
            }
            HStack(alignment: .top, spacing: 8) {
                VUMeter(needleDB: strip.needleDB)
                clipLight
            }
            muteButton
            labelled("Level") { levelKnob }
            Text(Gain.label(db: strip.db))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Panel.ink(scheme))
            stateLabel
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 8)
        .frame(width: Self.width)
        .opacity(strip.connected ? 1 : 0.4)
        .disabled(!strip.connected)
    }

    // MARK: Name and state

    @ViewBuilder private var nameView: some View {
        if editing {
            TextField("Name", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { mixer.rename(strip, draft); editing = false }
                .onExitCommand { editing = false }
        } else {
            Text(strip.displayName)
                .engraved(size: 14)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 22)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { draft = strip.displayName; editing = true }
                .help("Double-click to rename")
        }
    }

    @ViewBuilder private var stateLabel: some View {
        if !strip.connected {
            Text("Disconnected").engraved(size: 10)
        } else if strip.noSignal {
            Text("No signal").engraved(size: 10).opacity(0.7)
        } else {
            Text(" ").engraved(size: 10)
        }
    }

    // MARK: Buttons

    private var defaultButton: some View {
        let lit = strip.isDefaultInput
        return Button { mixer.makeDefaultInput(strip) } label: {
            Text("DEFAULT")
                .font(.custom("Avenir Next Condensed", size: 10).weight(.bold))
                .tracking(1.2)
                .foregroundStyle(lit ? Color(red: 0.25, green: 0.12, blue: 0) : Color(white: 0.5))
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(Capsule().fill(lit
                    ? LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.55), Color(red: 1, green: 0.68, blue: 0.25)],
                                     startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [Color(white: 0.2), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)))
                .overlay(Capsule().stroke(.black.opacity(0.6), lineWidth: 1))
                .shadow(color: lit ? Color.orange.opacity(0.7) : .clear, radius: 6)
        }
        .buttonStyle(.plain)
        .help("Make this the default input")
        .accessibilityValue(lit ? "On" : "Off")
    }

    private var muteButton: some View {
        let lit = strip.muted
        return VStack(spacing: 3) {
            Button { mixer.toggleMute(strip) } label: {
                Circle()
                    .fill(lit ? RadialGradient(colors: [Color(red: 1, green: 0.45, blue: 0.4), Color(red: 0.85, green: 0.05, blue: 0.05)],
                                               center: .init(x: 0.4, y: 0.35), startRadius: 0, endRadius: 16)
                              : RadialGradient(colors: [Color(white: 0.22), Color(white: 0.06)],
                                               center: .init(x: 0.4, y: 0.35), startRadius: 0, endRadius: 16))
                    .frame(width: 26, height: 26)
                    .padding(3)
                    .overlay(Circle().stroke(Color(red: 0.8, green: 0.1, blue: 0.08), lineWidth: 2.5))
                    .shadow(color: lit ? .red.opacity(0.8) : .clear, radius: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mute")
            .accessibilityValue(lit ? "On" : "Off")
            Text("Mute").engraved()
        }
    }

    private var clipLight: some View {
        let lit = strip.clipLit
        return VStack(spacing: 4) {
            Button { mixer.clearClip(strip) } label: {
                Circle()
                    .fill(RadialGradient(colors: lit ? [Color(red: 1, green: 0.6, blue: 0.5), .red]
                                                     : [Color(red: 0.4, green: 0.1, blue: 0.1), Color(red: 0.15, green: 0.02, blue: 0.02)],
                                         center: .init(x: 0.4, y: 0.35), startRadius: 0, endRadius: 8))
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(.black.opacity(0.7), lineWidth: 1))
                    .shadow(color: lit ? .red : .clear, radius: 5)
            }
            .buttonStyle(.plain)
            .help("Clip light. Click to clear.")
            .accessibilityLabel("Clip light")
            .accessibilityValue(lit ? "Lit" : "Off")
            Text("Clip").engraved(size: 8).fixedSize()
        }
    }

    // MARK: Knobs

    private func labelled<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 2) {
            content()
            Text(title).engraved(size: 9).lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private var deviceGainKnob: some View {
        let value = strip.deviceGain
        return Knob(style: .small, fraction: value ?? 0, enabled: value != nil,
                    label: "Device gain", valueText: "\(Int(((value ?? 0) * 100).rounded())) percent",
                    set: { mixer.setDeviceGain(strip, $0) })
    }

    private var trimKnob: some View {
        Knob(style: .small, fraction: (strip.trimDB + 24) / 48,
             label: "Trim", valueText: String(format: "%+.1f dB", strip.trimDB),
             set: { mixer.setTrim(strip, $0 * 48 - 24) },
             reset: { mixer.setTrim(strip, 0) })
    }

    private var levelKnob: some View {
        let ticks = [-Float.infinity, -40, -20, -10, -5, 0, 5, 10].map { Gain.position(db: $0) }
        return Knob(style: .chrome, fraction: strip.position, ticks: ticks, bigTick: Gain.position(db: 0),
                    label: "Level", valueText: Gain.label(db: strip.db),
                    set: { mixer.setPosition(strip, Gain.snapped($0)) },
                    reset: { mixer.setPosition(strip, Gain.detent) })
    }
}
